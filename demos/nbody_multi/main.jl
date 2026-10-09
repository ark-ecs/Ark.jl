
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
Creates the world: all bodies start in a single table (like demos/nbody), and
the two black holes live in their own table (extra `BlackHole` tag). Components
use GPU storages (including the `CPU()` back-end), which [`FlatQuery`](@ref)
requires.
"""
function nbody_world(n, dt, backend; bh=BlackHoleConfig(1.0f6, 350.0f0), seed=42)
    storage = Storage(GPUStructArray, backend)
    world = World(
        Position => storage,
        Velocity => storage,
        Mass => storage,
        BlackHole,
    )

    add_resource!(world, TimeStep(dt))
    add_resource!(world, NParticles(n))
    add_resource!(world, bh)

    Random.seed!(seed)
    initialize!(NBodyPhysics(), world)
    return world
end

function nbody_simulation(n, dt, backend; bh=BlackHoleConfig(1.0f6, 350.0f0))
    world = nbody_world(n, dt, backend; bh)

    q = FlatQuery(world, Filter(world, (Position, Velocity, Mass)))
    @info "FlatQuery" entities=length(q)
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

function main(backend)
    n, dt = 10000, 0.01f0
    nbody_simulation(n, dt, backend)
end

# ---------------------------------------------------------------------------
# Verification: the FlatQuery launch must reproduce true all-pairs physics
# across table boundaries. Both black holes live in their own table from the
# start, so the flat views span two tables on every single update.
# ---------------------------------------------------------------------------

const BodyState = Tuple{Float32,Float32,Float32}

function snapshot!(pos, vel, mass, world)
    empty!(pos)
    empty!(vel)
    empty!(mass)
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

function verify_nbody_multi(backend; n=160, dt=0.01f0, steps=6)
    config = BlackHoleConfig(1.0f6, 120.0f0)
    world = nbody_world(n, dt, backend; bh=config, seed=1234)

    # Reference initial state, taken from the world (query order defines the
    # index space; this includes both black holes in their table).
    pos = BodyState[]
    vel = BodyState[]
    mass = Float32[]
    snapshot!(pos, vel, mass, world)
    @assert length(pos) == n + 2

    # Run the world with the FlatQuery-based physics.
    for _ in 1:steps
        update!(NBodyPhysics(), world, backend)
    end
    KernelAbstractions.synchronize(backend)

    # Run the reference, all pairs.
    ref_pos = copy(pos)
    ref_vel = copy(vel)
    ref_mass = copy(mass)
    for _ in 1:steps
        reference_step!(ref_pos, ref_vel, ref_mass, dt)
    end

    got_pos = BodyState[]
    got_vel = BodyState[]
    world_state!(got_pos, got_vel, world)

    # The black holes must live in their own table, and the flat views must
    # cover every body in both tables.
    ntables = count(_ -> true, Query(world, (Position, Velocity, Mass)))
    @assert ntables == 2 "expected 2 tables (bodies + black holes), got $ntables"
    q = FlatQuery(world, Filter(world, (Position, Velocity, Mass)))
    @assert length(q) == n + 2
    close!(q)

    dev = max_deviation(got_pos, ref_pos)
    @info "Results" entities=(n + 2) tables=ntables deviation=dev
    @assert dev < 1e-2 "FlatQuery physics deviates from the all-pairs reference: $dev"

    println("verified: FlatQuery physics matches the all-pairs reference across")
    println("both tables, including the two black holes")
    return
end
