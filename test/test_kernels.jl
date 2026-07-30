
using KernelAbstractions

@kernel function move_kernel(positions, velocities, dt)
    i = @index(Global)
    positions.x[i] += velocities.dx[i] * dt
    positions.y[i] += velocities.dy[i] * dt
end

@kernel function heal_kernel(healths, amount)
    i = @index(Global)
    healths[i] = Health(healths[i].health + amount)
end

@testset "KernelAbstractions kernels on the :CPU back-end" begin
    backend = CPU()
    world = TestWorld(
        Position => Storage{GPUStructArray{:CPU}},
        Velocity => Storage{GPUStructArray{:CPU}},
        Health => Storage{GPUVector{:CPU}},
    )

    n = 64
    entities = [
        new_entity!(world, (Position(i, 2i), Velocity(1, 2), Health(i)))
        for i in 1:n
    ]

    dt = 0.5
    move = move_kernel(backend)
    heal = heal_kernel(backend)

    for (es, positions, velocities, healths) in Query(world, (Position, Velocity, Health))
        m = length(es)
        move(unpack(positions), unpack(velocities), dt; ndrange=m)
        KernelAbstractions.synchronize(backend)
        heal(healths, 10.0; ndrange=m)
        KernelAbstractions.synchronize(backend)
    end

    for (i, e) in enumerate(entities)
        pos, health = get_components(world, e, (Position, Health))
        @test pos == Position(i + 1 * dt, 2i + 2 * dt)
        @test health == Health(i + 10.0)
    end

    reset!(world)
end

@testset "KernelAbstractions kernels write through to the backing memory" begin
    backend = CPU()

    gv = GPUVector{:CPU,Health,Vector{Health}}()
    resize!(gv, 8)
    fill!(gv.host, Health(0))

    heal_kernel(backend)(_gpuvector_view(gv, 3:5), 1.0; ndrange=3)
    KernelAbstractions.synchronize(backend)

    @test gv[1] == Health(0)
    @test gv[3] == Health(1) && gv[4] == Health(1) && gv[5] == Health(1)
    @test gv[6] == Health(0)
end
