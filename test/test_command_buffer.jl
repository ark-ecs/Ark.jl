
@testset "CommandBuffer constructor validation" begin
    world = World(Position)

    buf = CommandBuffer(world, ((new_entity!, (Position,)), (remove_entity!,)))
    @test buf isa CommandBuffer

    @test_throws ArgumentError CommandBuffer(world, ((sin,),))

    world_exchange = World(Position, Velocity, Health)
    @test_throws ArgumentError CommandBuffer(world_exchange, ((exchange_components!, (Health,), (Velocity,)),))
end

@testset "CommandBuffer new_entity!" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, ((new_entity!, (Position, Velocity)),))

    e = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
    @test e isa StagedEntity
    @test !is_alive(world, e)

    apply!(world, buf)
    @test is_alive(world, e.entity)
    pos, = get_components(world, e.entity, (Position,))
    @test pos == Position(1.0, 2.0)
    vel, = get_components(world, e.entity, (Velocity,))
    @test vel == Velocity(10.0, 20.0)
end

@testset "CommandBuffer new_entity! multiple" begin
    world = World(Position)
    buf = CommandBuffer(world, ((new_entity!, (Position,)),))

    e1 = new_entity!(world, buf, (Position(1.0, 2.0),))
    e2 = new_entity!(world, buf, (Position(3.0, 4.0),))
    @test e1 != e2

    apply!(world, buf)
    pos1, = get_components(world, e1.entity, (Position,))
    pos2, = get_components(world, e2.entity, (Position,))
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

@testset "CommandBuffer add_components! relations" begin
    world = World(Position, Relation{ChildOf})
    buf = CommandBuffer(world, ((add_components!, (ChildOf,)),))

    parent = new_entity!(world, (Position(1.0, 2.0),))
    child = new_entity!(world, (Position(3.0, 4.0),))
    add_components!(world, buf, child, (ChildOf() => parent,))
    apply!(world, buf)

    target, = get_relations(world, child, (ChildOf,))
    @test target == parent
end

@testset "CommandBuffer set_components!" begin
    world = World(Position, Velocity)
    buf = CommandBuffer(world, ((set_components!, (Position, Velocity)),))

    e = new_entity!(world, (Position(0.0, 0.0), Velocity(1.0, 1.0)))
    set_components!(world, buf, e, (Position(2.0, 3.0), Velocity(4.0, 5.0)))
    apply!(world, buf)

    pos, vel = get_components(world, e, (Position, Velocity))
    @test pos == Position(2.0, 3.0)
    @test vel == Velocity(4.0, 5.0)
end

@testset "CommandBuffer set_relations!" begin
    world = World(Position, Relation{ChildOf})
    buf = CommandBuffer(world, ((set_relations!, (ChildOf,)),))

    parent1 = new_entity!(world, (Position(1.0, 2.0),))
    parent2 = new_entity!(world, (Position(3.0, 4.0),))
    child = new_entity!(world, (Position(5.0, 6.0), ChildOf() => parent1))

    set_relations!(world, buf, child, (ChildOf => parent2,))
    apply!(world, buf)

    target, = get_relations(world, child, (ChildOf,))
    @test target == parent2
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
    buf = CommandBuffer(world, ((exchange_components!, (add=(Health,), remove=(Velocity,))),))

    e = new_entity!(world, (Position(0.0, 0.0), Velocity(1.0, 1.0)))
    exchange_components!(world, buf, e; add=(Health(100.0),), remove=(Velocity,))
    apply!(world, buf)

    @test has_components(world, e, (Position, Health))
    @test !has_components(world, e, (Velocity,))
    health, = get_components(world, e, (Health,))
    @test health == Health(100.0)
end

@testset "CommandBuffer exchange_components! add relation" begin
    world = World(Position, Velocity, Relation{ChildOf})
    buf = CommandBuffer(world, ((exchange_components!, (add=(ChildOf,), remove=(Velocity,))),))

    parent = new_entity!(world, (Position(1.0, 2.0),))
    child = new_entity!(world, (Position(3.0, 4.0), Velocity(1.0, 1.0)))
    exchange_components!(world, buf, child; add=(ChildOf() => parent,), remove=(Velocity,))
    apply!(world, buf)

    target, = get_relations(world, child, (ChildOf,))
    @test target == parent
    @test !has_components(world, child, (Velocity,))
end

@testset "CommandBuffer combined operations" begin
    world = World(Position, Velocity, Health)
    buf = CommandBuffer(
        world,
        (
            (new_entity!, (Position, Velocity)),
            (remove_entity!,),
            (add_components!, (Health,)),
            (remove_components!, (Velocity,)),
            (exchange_components!, (add=(Health,), remove=(Velocity,))),
        ),
    )

    e1 = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
    e2 = new_entity!(world, buf, (Position(3.0, 4.0), Velocity(30.0, 40.0)))

    add_components!(world, buf, e1, (Health(100.0),))
    remove_components!(world, buf, e1, (Velocity,))
    remove_entity!(world, buf, e2)

    e3 = new_entity!(world, (Position(5.0, 6.0), Velocity(1.0, 1.0)))
    exchange_components!(world, buf, e3; add=(Health(100.0),), remove=(Velocity,))

    apply!(world, buf)

    @assert is_alive(world, e1.entity)
    @assert !is_alive(world, e2.entity)
    @assert is_alive(world, e3)

    @test has_components(world, e1.entity, (Position, Health))
    @test !has_components(world, e1.entity, (Velocity,))
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
    @test has_components(world, e.entity, (Position,))
    @test !has_components(world, e.entity, (Velocity,))
end

@testset "CommandBuffer new_entity! relations" begin
    world = World(Position, Relation{ChildOf})
    buf = CommandBuffer(world, (
        (new_entity!, (Position,)),
        (new_entity!, (Position, ChildOf)),
    ))

    parent = new_entity!(world, buf, (Position(1.0, 2.0),))
    child = new_entity!(world, buf, (Position(3.0, 4.0), ChildOf() => parent.entity))
    apply!(world, buf)

    target, = get_relations(world, child.entity, (ChildOf,))
    pos, = get_components(world, child.entity, (Position,))
    @test target == parent.entity
    @test pos == Position(3.0, 4.0)
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

    pos1, = get_components(world, e1.entity, (Position,))
    pos2, = get_components(world, e2.entity, (Position,))
    pos3, = get_components(world, e3, (Position,))
    @test pos1 == Position(1.0, 2.0)
    @test pos2 == Position(3.0, 4.0)
    @test pos3 == Position(5.0, 6.0)
    @test is_alive(world, e1.entity)
    @test is_alive(world, e2.entity)
    @test is_alive(world, e3)

    remove_entity!(world, e2.entity)
    @test is_alive(world, e1.entity)
    @test !is_alive(world, e2.entity)
    @test is_alive(world, e3)
end
