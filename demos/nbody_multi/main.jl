
using Ark
using KernelAbstractions
using Random

const IS_CI = "CI" in keys(ENV)
const VERIFY_ONLY = IS_CI || "--verify" in ARGS

include("resources.jl")
include("components.jl")
include("sys/nbody_physics.jl")

if !VERIFY_ONLY
    using GLMakie
    include("sys/nbody_plot.jl")
end

"""
Creates the multi-table world: bodies are spread over `clusters` tables using a
relation, all belonging to the same archetype. Components use GPU storages
(including the `CPU()` back-end), which [`FlatQuery`](@ref) requires.
"""
function nbody_world(n, dt, backend, clusters; seed=42)
    storage = Storage(GPUStructArray, backend)
    world = World(
        Position => storage,
        Velocity => storage,
        Mass => storage,
        Relation{Cluster},
    )

    add_resource!(world, TimeStep(dt))
    add_resource!(world, NParticles(n))

    Random.seed!(seed)
    targets = initialize!(NBodyPhysics(), world, clusters)
    return world, targets
end

function nbody_simulation(n, dt, backend; clusters=8)
    world, _ = nbody_world(n, dt, backend, clusters)

    The flat query reports what it covers: all entities, spread over `clusters` tables.
    q = FlatQuery(world, Filter(world, (Position, Velocity, Mass)))
    @info "FlatQuery" entities=length(q) tables=q._ntables
    close!(q)

    initialize!(NBodyPlot(), world)

    fig = get_resource(world, WorldFigure).figure
    display(fig)

    GC.gc()

    k = 0
    while isopen(fig.scene)
        t0 = time_ns()

        update!(NBodyPhysics(), world, backend)
        update!(NBodyPlot(), world)

        t1 = time_ns()

        fps_obs = get_resource(world, WorldObservables).fps
        fps_obs[] = "FPS: $(round(1e9 / (t1 - t0), digits=1))"
        sleep(max(0, 1 / 60 - (t1 - t0) / 1e9))
        yield()

        k += 1
        IS_CI && k == 2 && return
    end
end

# ---------------------------------------------------------------------------
# Verification: with bodies spread over multiple tables, the FlatQuery launch must
# reproduce true all-pairs physics. Per-table launches only compute interactions
# within each table and therefore diverge.
# ---------------------------------------------------------------------------

const BodyState = Tuple{Float32,Float32,Float32}

function snapshot!(pos, vel, mass, world)
    empty!(pos); empty!(vel); empty!(mass)
    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        (px, py, pz) = unpack(positions)
        (vx, vy, vz) = unpack(velocities)
        mv = unpack(masses).val
        for i in eachindex(px)
            push!(pos, (px[i], py[i], pz[i]))
            push!(vel, (vx[i], vy[i], vz[i]))
            push!(mass, mv[i])
        end
    end
    return
end

# Brute-force all-pairs acceleration on the host, same math and order as the kernel.
function reference_acceleration!(acc, pos, mass, n)
    for i in 1:n
        px_i, py_i, pz_i = pos[i]
        accx = accy = accz = 0.0f0
        for j in 1:n
            i == j && continue
            px_j, py_j, pz_j = pos[j]
            dx = px_j - px_i
            dy = py_j - py_i
            dz = pz_j - pz_i
            dist_sq = dx * dx + dy * dy + dz * dz + SOFTEN
            inv_dist = 1.0f0 / sqrt(dist_sq)
            inv_dist3 = inv_dist * inv_dist * inv_dist
            f = G * mass[j] * inv_dist3
            accx += f * dx
            accy += f * dy
            accz += f * dz
        end
        acc[i] = (accx, accy, accz)
    end
    return acc
end

# One reference step over all bodies, mirroring velocity_kernel + position_kernel.
function reference_step!(pos, vel, mass, dt)
    n = length(pos)
    acc = reference_acceleration!(Vector{BodyState}(undef, n), pos, mass, n)
    for i in 1:n
        vx, vy, vz = vel[i]
        ax, ay, az = acc[i]
        vx += ax * dt
        vy += ay * dt
        vz += az * dt
        vel[i] = (vx, vy, vz)
        px, py, pz = pos[i]
        pos[i] = (px + vx * dt, py + vy * dt, pz + vz * dt)
    end
    return
end

# What per-table launches compute: interactions only within each table. Tables
# are reconstructed from the relation targets, so this mirrors the old
# one-launch-per-table behavior of demos/nbody.
function pertable_reference!(pos, vel, mass, dt, tables)
    for tbl in tables
        n = length(tbl)
        acc = Vector{BodyState}(undef, n)
        for i in 1:n
            gi = tbl[i]
            px_i, py_i, pz_i = pos[gi]
            accx = accy = accz = 0.0f0
            for j in 1:n
                gj = tbl[j]
                gj == gi && continue
                px_j, py_j, pz_j = pos[gj]
                dx = px_j - px_i
                dy = py_j - py_i
                dz = pz_j - pz_i
                dist_sq = dx * dx + dy * dy + dz * dz + SOFTEN
                inv_dist = 1.0f0 / sqrt(dist_sq)
                inv_dist3 = inv_dist * inv_dist * inv_dist
                f = G * mass[gj] * inv_dist3
                accx += f * dx
                accy += f * dy
                accz += f * dz
            end
            acc[i] = (accx, accy, accz)
        end
        for i in 1:n
            gi = tbl[i]
            vx, vy, vz = vel[gi]
            ax, ay, az = acc[i]
            vx += ax * dt
            vy += ay * dt
            vz += az * dt
            vel[gi] = (vx, vy, vz)
            px, py, pz = pos[gi]
            pos[gi] = (px + vx * dt, py + vy * dt, pz + vz * dt)
        end
    end
    return
end

function world_state!(pos, vel, world)
    mass = Float32[]
    snapshot!(pos, vel, mass, world)
    return
end

function max_deviation(a, b)
    m = 0.0
    for i in eachindex(a)
        ai, bi = a[i], b[i]
        d = sqrt((ai[1]-bi[1])^2 + (ai[2]-bi[2])^2 + (ai[3]-bi[3])^2)
        m = max(m, d)
    end
    return m
end

function verify_nbody_multi(backend; n=160, dt=0.01f0, clusters=4, steps=5)
    # FlatQuery world: the physics under test. Heavy masses make cross-table
    # interactions dominant, so missing them is clearly measurable.
    world, targets = nbody_world(n, dt, backend, clusters; seed=1234)

    # Table layout check: the relation must have produced multiple tables.
    q = FlatQuery(world, Filter(world, (Position, Velocity, Mass)))
    @assert q._ntables == clusters "expected $clusters tables, got $(q._ntables)"
    @assert length(q) == n
    @info "Verification setup" entities=n tables=q._ntables backend=typeof(backend)
    close!(q)

    # Reference initial state, taken from the world (query order defines the index
    # space; for a freshly built world this is table/creation order).
    pos = BodyState[]; vel = BodyState[]; mass = Float32[]
    snapshot!(pos, vel, mass, world)

    # Run the world with the q-based physics.
    for _ in 1:steps
        update!(NBodyPhysics(), world, backend)
    end
    KernelAbstractions.synchronize(backend)

    # Run the reference, all pairs across all tables.
    ref_pos = copy(pos); ref_vel = copy(vel)
    for _ in 1:steps
        reference_step!(ref_pos, ref_vel, mass, dt)
    end

    # What per-table launches would have computed.
    per_pos = copy(pos); per_vel = copy(vel)
    per = cld(n, clusters)
    tables = [collect((c-1)*per .+ (1:min(per, n - (c-1)*per))) for c in 1:clusters]
    for _ in 1:steps
        pertable_reference!(per_pos, per_vel, mass, dt, tables)
    end

    got_pos = BodyState[]; got_vel = BodyState[]
    world_state!(got_pos, got_vel, world)

    dev_flat = max_deviation(got_pos, ref_pos)
    dev_per = max_deviation(per_pos, ref_pos)
    @info "Results" flat_vs_reference=dev_flat pertable_vs_reference=dev_per

    @assert dev_flat < 1e-2 "q physics deviates from the all-pairs reference: $dev_flat"
    @assert dev_per > 1e-2 "per-table launches should diverge from the all-pairs reference when bodies q multiple tables, but deviation was only $dev_per"

    println("verified: FlatQuery launch matches all-pairs physics across $clusters tables,")
    println("while per-table launches miss cross-table interactions (deviation $dev_per)")
    return
end
