
struct NBodyPhysics end

const G = 1.0f0
const SOFTEN = 0.1f0

@kernel function velocity_kernel(positions, velocities, masses, n, dt)
    i = @index(Global)

    px, py, pz = positions
    px_i = px[i]
    py_i = py[i]
    pz_i = pz[i]

    accx = accy = accz = 0.0f0

    for j in 1:n
        i == j && continue

        @inbounds px_j, py_j, pz_j = px[j], py[j], pz[j]

        dx = px_j - px_i
        dy = py_j - py_i
        dz = pz_j - pz_i

        dist_sq = dx * dx + dy * dy + dz * dz + SOFTEN
        inv_dist = 1.0f0 / sqrt(dist_sq)
        inv_dist3 = inv_dist * inv_dist * inv_dist

        @inbounds m_j = masses.val[j]
        f = G * m_j * inv_dist3

        accx += f * dx
        accy += f * dy
        accz += f * dz
    end

    vx, vy, vz = velocities

    vx[i] += accx * dt
    vy[i] += accy * dt
    vz[i] += accz * dt
end

@kernel function position_kernel(positions, velocities, dt)
    i = @index(Global)

    positions.x[i] += velocities.x[i] * dt
    positions.y[i] += velocities.y[i] * dt
    positions.z[i] += velocities.z[i] * dt
end

function initialize!(::NBodyPhysics, world)
    n = get_resource(world, NParticles).n
    for i in 1:n
        new_entity!(
            world,
            (
                Position(((randn(), randn(), randn()) .* 50.0f0)...),
                Velocity(((randn(), randn(), randn()) .* 0.01f0)...),
                Mass(randexp() * 10.0f0),
            ),
        )
    end
    create_black_holes!(world)
    return
end

# Deterministic initial states derived from the config, mirrored to the left
# and right of the cloud, so that the headless verification can reproduce the
# black holes on the host.
function black_hole_states(config::BlackHoleConfig)
    dir = (0.8f0, 0.45f0, -0.35f0)
    norm = sqrt(dir[1]^2 + dir[2]^2 + dir[3]^2)
    off = dir .* (config.distance / norm)
    vel = (-0.5f0, -0.25f0, 0.2f0) # slow drift toward the cloud
    return (
        (Position(off...), Velocity(vel...), Mass(config.mass)),
        (Position(-off[1], off[2], off[3]), Velocity(-vel[1], vel[2], vel[3]), Mass(config.mass)),
    )
end

function create_black_holes!(world)
    states = black_hole_states(get_resource(world, BlackHoleConfig))
    return new_entity!.(Ref(world), ((p, v, m, BlackHole()) for (p, v, m) in states))
end

function update!(::NBodyPhysics, world, backend)
    dt = get_resource(world, TimeStep).dt
    vkernel = velocity_kernel(backend)
    pkernel = position_kernel(backend)

    # One query over all matching tables: a single launch per kernel, covering
    # all bodies. The black holes carry the extra BlackHole tag and live in
    # their own table, so the flat views span two tables and the all-pairs
    # interaction automatically includes them.
    q = FlatQuery(world, Filter(world, (Position, Velocity, Mass)))
    n = length(q)
    positions = q[Position]
    velocities = q[Velocity]
    masses = q[Mass]

    vkernel(unpack(positions), unpack(velocities), unpack(masses),
        n, dt, ndrange=n, workgroupsize=256)
    pkernel(unpack(positions), unpack(velocities),
        dt, ndrange=n, workgroupsize=256)

    # Required: the plot system reads the components from the host right after
    # this, and host code must not run while kernels are still in flight.
    # See "Synchronization with GPU Storages" in the manual, and
    # demos/gpu_hazards for what goes wrong otherwise.
    KernelAbstractions.synchronize(backend)
    close!(q)
end
