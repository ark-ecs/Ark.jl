
@testset "Filter basic functionality" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    f1 = Filter(world, (Position, Velocity))
    f2 = Filter(world, (Position, Velocity); with=(Altitude,))
    f3 = Filter(world, (Position, Velocity); without=(Altitude,))
    f4 = Filter(world, (Position, Velocity); exclusive=true)

    f5 = Filter(world, (Position, Velocity); register=true)
    @test length(_state(world)._cache.filters) == 1
    @test length(f5._filter.tables) == 0

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    @test length(f5._filter.tables) == 1
end

@testset "Filter table and entity counts" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    new_entities!(world, 10, (Position(0, 0),))
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(100)))

    filter1 = Filter(world, (Position, Velocity))
    @test count_tables(world, filter1) == 2
    @test count_entities(world, filter1) == 20

    filter2 = Filter(world, (Position, Velocity); register=true)
    @test count_tables(world, filter2) == 2
    @test count_entities(world, filter2) == 20
end

@testset "Issue #563" begin
    world = World(Dummy)
    e = new_entity!(world, (Dummy(),))

    filter = Filter(world, (Dummy,); register=true)
    @test isempty(collect(Query(world, filter))) == false

    filter = Filter(world, (Dummy,); register=false)
    @test isempty(collect(Query(world, filter))) == false

    remove_entity!(world, e)

    filter = Filter(world, (Dummy,); register=true)
    @test isempty(collect(Query(world, filter))) == true

    filter = Filter(world, (Dummy,); register=false)
    @test isempty(collect(Query(world, filter))) == true
end

@testset "Filter show" begin
    world = World(
        Position,
        Velocity,
        Altitude,
        Health,
        CompN{1},
    )
    filter = Filter(world, (Position, Velocity))
    @test string(filter) == "Filter((Position, Velocity))"

    filter = Filter(world, (Velocity, Position))
    @test string(filter) == "Filter((Velocity, Position))"

    filter = Filter(world, (Position, Velocity); optional=(Altitude,), with=(Health,), exclusive=true)
    @test string(filter) == "Filter((Position, Velocity); optional=(Altitude), with=(Health), exclusive=true)"

    filter = Filter(world, (Position, Velocity); optional=(Altitude,), without=(Health,))
    @test string(filter) == "Filter((Position, Velocity); optional=(Altitude), without=(Health))"

    filter = Filter(world, (Position, Velocity); register=true)
    @test string(filter) == "Filter((Position, Velocity); registered=true)"
end

@testset "Filter relation targets" begin
    world = World(Dummy, Position, Relation{ChildOf})
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())

    for i in 1:10
        new_entity!(world, (Position(i, i), ChildOf() => parent1))
        new_entity!(world, (Position(i, i), ChildOf() => parent2))
        new_entity!(world, (Position(i, i), ChildOf() => parent3))
    end

    filter = Filter(world, (Position,); with=(ChildOf => parent2,))
    @test count_tables(world, filter) == 1
    @test count_entities(world, filter) == 10
end
