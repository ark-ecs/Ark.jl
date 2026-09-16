
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

function initialize!(::NBodyPhysics, world, clusters)
    n = get_resource(world, NParticles).n
    targets = [new_entity!(world, ()) for _ in 1:clusters]
    per_cluster = cld(n, clusters)
    created = 0
    for c in 1:clusters
        for i in 1:(c == clusters ? n - created : per_cluster)
            created += 1
            new_entity!(
                world,
                (
                    Position(((randn(), randn(), randn()) .* 50.0f0)...),
                    Velocity(((randn(), randn(), randn()) .* 0.01f0)...),
                    # Heavy masses so that cross-table interactions are significant.
                    Mass(randexp() * 1000.0f0),
                    Cluster() => targets[c],
                ),
            )
        end
    end
    return targets
end

function update!(::NBodyPhysics, world, backend)
    dt = get_resource(world, TimeStep).dt
    vkernel = velocity_kernel(backend)
    pkernel = position_kernel(backend)

    # One q over all matching tables: a single launch per kernel, covering all
    # entities. Because the views q every table, the all-pairs interaction in
    # `velocity_kernel` also acts across table boundaries - which per-table
    # launches (as in demos/nbody) would silently miss.
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
end
