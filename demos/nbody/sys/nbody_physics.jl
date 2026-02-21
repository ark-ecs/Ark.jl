
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
end

function update!(::NBodyPhysics, world, backend)
    dt = get_resource(world, TimeStep).dt
    n = get_resource(world, NParticles).n
    vkernel = velocity_kernel(backend)
    pkernel = position_kernel(backend)

    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        vkernel(unpack(positions), unpack(velocities), unpack(masses),
            n, dt, ndrange=n, workgroupsize=256)
        KernelAbstractions.synchronize(backend)
        pkernel(unpack(positions), unpack(velocities),
            dt, ndrange=n, workgroupsize=256)
        KernelAbstractions.synchronize(backend)
    end
end
