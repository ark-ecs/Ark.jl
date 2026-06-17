
@testset "CommandBuffer constructor validation" begin
    world = World(Position)

    buf = CommandBuffer(world, ((new_entity!, (Position,)), (remove_entity!,)))
    @test buf isa CommandBuffer

    @test_throws ArgumentError CommandBuffer(world, ((sin,),))
end

@testset "CommandBuffer new_entity!" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, ((new_entity!, (Position, Velocity)),))

    e = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
    @test e isa Entity
    @test is_alive(world, e)

    apply!(world, buf)
    @test is_alive(world, e)
    pos, = get_components(world, e, (Position,))
    @test pos == Position(1.0, 2.0)
    vel, = get_components(world, e, (Velocity,))
    @test vel == Velocity(10.0, 20.0)
end

@testset "CommandBuffer new_entity! multiple" begin
    world = World(Position)
    buf = CommandBuffer(world, ((new_entity!, (Position,)),))

    e1 = new_entity!(world, buf, (Position(1.0, 2.0),))
    e2 = new_entity!(world, buf, (Position(3.0, 4.0),))
    @test e1 != e2

    apply!(world, buf)
    pos1, = get_components(world, e1, (Position,))
    pos2, = get_components(world, e2, (Position,))
    @test pos1 == Position(1.0, 2.0)
    @test pos2 == Position(3.0, 4.0)
end

@testset "CommandBuffer remove_entity!" begin
    world = World(Position)
    buf = CommandBuffer(world, ((remove_entity!,),))

    e = new_entity!(world, (Position(1.0, 2.0),))
    @test is_alive(world, e)

    remove_entity!(world, buf, e)
    apply!(world, buf)
    @test !is_alive(world, e)
end

@testset "CommandBuffer add_components!" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, ((add_components!, (Velocity,)),))

    e = new_entity!(world, (Position(0.0, 0.0),))
    add_components!(world, buf, e, (Velocity(5.0, 5.0),))
    apply!(world, buf)

    vel, = get_components(world, e, (Velocity,))
    @test vel == Velocity(5.0, 5.0)
end

@testset "CommandBuffer remove_components!" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, ((remove_components!, (Velocity,)),))

    e = new_entity!(world, (Position(0.0, 0.0), Velocity(1.0, 1.0)))
    remove_components!(world, buf, e, (Velocity,))
    apply!(world, buf)

    @test has_components(world, e, (Position,))
    @test !has_components(world, e, (Velocity,))
end

@testset "CommandBuffer exchange_components!" begin
    world = World(Position, Velocity, Health)
    buf = CommandBuffer(world, ((exchange_components!, (Health,), (Velocity,)),))

    e = new_entity!(world, (Position(0.0, 0.0), Velocity(1.0, 1.0)))
    exchange_components!(world, buf, e; add=(Health(100.0),), remove=(Velocity,))
    apply!(world, buf)

    @test has_components(world, e, (Position, Health))
    @test !has_components(world, e, (Velocity,))
    health, = get_components(world, e, (Health,))
    @test health == Health(100.0)
end

@testset "CommandBuffer combined operations" begin
    world = World(Position, Velocity, Health)
    buf = CommandBuffer(world, (
        (new_entity!, (Position, Velocity)),
        (remove_entity!,),
        (add_components!, (Health,)),
        (remove_components!, (Velocity,)),
        (exchange_components!, (Health,), (Velocity,)),
    ))

    e1 = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
    e2 = new_entity!(world, buf, (Position(3.0, 4.0), Velocity(30.0, 40.0)))

    add_components!(world, buf, e1, (Health(100.0),))
    remove_components!(world, buf, e1, (Velocity,))
    remove_entity!(world, buf, e2)

    e3 = new_entity!(world, (Position(5.0, 6.0), Velocity(1.0, 1.0)))
    exchange_components!(world, buf, e3; add=(Health(100.0),), remove=(Velocity,))

    apply!(world, buf)

    @assert is_alive(world, e1)
    @assert !is_alive(world, e2)
    @assert is_alive(world, e3)

    @test has_components(world, e1, (Position, Health))
    @test !has_components(world, e1, (Velocity,))
    @test has_components(world, e3, (Position, Health))
    @test !has_components(world, e3, (Velocity,))
end

@testset "CommandBuffer pre-allocated entity usable immediately" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, (
        (new_entity!, (Position, Velocity)),
        (remove_components!, (Velocity,)),
    ))

    e = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
    remove_components!(world, buf, e, (Velocity,))

    apply!(world, buf)
    @test has_components(world, e, (Position,))
    @test !has_components(world, e, (Velocity,))
end

@testset "CommandBuffer empty apply" begin
    world = World(Position)
    buf = CommandBuffer(world, ((remove_entity!,),))
    apply!(world, buf)
end

@testset "CommandBuffer reuse after apply" begin
    world = World(Position)
    buf = CommandBuffer(world, ((new_entity!, (Position,)),))

    e1 = new_entity!(world, buf, (Position(1.0, 2.0),))
    apply!(world, buf)

    e2 = new_entity!(world, buf, (Position(3.0, 4.0),))
    apply!(world, buf)

    e3 = new_entity!(world, (Position(5.0, 6.0),))

    pos1, = get_components(world, e1, (Position,))
    pos2, = get_components(world, e2, (Position,))
    pos3, = get_components(world, e3, (Position,))
    @test pos1 == Position(1.0, 2.0)
    @test pos2 == Position(3.0, 4.0)
    @test pos3 == Position(5.0, 6.0)
    @test is_alive(world, e1)
    @test is_alive(world, e2)
    @test is_alive(world, e3)

    remove_entity!(world, e2)
    @test is_alive(world, e1)
    @test !is_alive(world, e2)
    @test is_alive(world, e3) 
end
