
@testset "Cache functionality" begin
    world = World(Dummy, Position, Velocity, Relation{ChildOf}, Altitude)

    filter1 = Filter(world, (); register=true)
    @test length(_state(world)._cache.filters) == 1
    @test length(filter1._filter.tables) == 1
    @test filter1._filter.id[] == 1
    @test _state(world)._tables[1].filters[].ids == [UInt32(1)]

    filter2 = Filter(world, (Altitude,); register=true)
    @test length(_state(world)._cache.filters) == 2
    @test length(filter2._filter.tables) == 0
    @test filter2._filter.id[] == 2

    parent = new_entity!(world, ())
    e1 = new_entity!(world, (Position(0, 0), Velocity(0, 0)))

    @test length(filter1._filter.tables) == 2

    filter3 = Filter(world, (Position, Velocity); register=true)
    @test length(_state(world)._cache.filters) == 3
    @test length(filter3._filter.tables) == 1
    @test filter3._filter.id[] == 3

    unregister!(world, filter1)
    @test _state(world)._cache.free_indices == [UInt32(1)]
    @test length(filter1._filter.tables) == 0
    @test filter1._filter.id[] == 0
    @test _state(world)._tables[1].filters[].ids == []

    unregister!(world, filter3)
    @test _state(world)._cache.free_indices == [UInt32(1)]
    @test length(_state(world)._cache.filters) == 2
    @test length(filter3._filter.tables) == 0

    @test_throws(
        "InvalidStateException: filter is not registered to the cache",
        unregister!(world, filter3)
    )

    filter3 = Filter(world, (Position, Velocity); register=true)
    @test length(_state(world)._cache.filters) == 2
    @test length(filter3._filter.tables) == 1
    @test filter3._filter.id[] == 1
end

@testset "Cache functionality relations" begin
    world = World(Dummy, Position, Velocity, Relation{ChildOf})

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    filter1 = Filter(world, (ChildOf,); register=true)
    filter2 = Filter(world, (ChildOf => parent1,); register=true)

    e1 = new_entity!(world, (ChildOf() => parent1,))
    e2 = new_entity!(world, (ChildOf() => parent2,))

    @test length(_state(world)._tables[2].filters[]) == 2
    @test length(_state(world)._tables[3].filters[]) == 1

    filter3 = Filter(world, (ChildOf => parent2,); register=true)

    @test length(filter1._filter.tables) == 2
    @test length(filter2._filter.tables) == 1
    @test length(filter3._filter.tables) == 1

    @test length(_state(world)._tables[2].filters[]) == 2
    @test length(_state(world)._tables[3].filters[]) == 2

    remove_entity!(world, e1)
    remove_entity!(world, e2)
    remove_entity!(world, parent1)
    remove_entity!(world, parent2)

    @test length(filter1._filter.tables) == 0
    @test length(filter2._filter.tables) == 0
    @test length(filter3._filter.tables) == 0

    @test length(_state(world)._tables[2].filters[]) == 0
    @test length(_state(world)._tables[3].filters[]) == 0
end

@testset "Add to unregistered filter Issue #499" begin
    world = World(Position, Relation{ChildOf})
    f1 = Filter(world, (Position,); register=true)
    f2 = Filter(world, (Position,); register=true)
    unregister!(world, f1)
    parent = new_entity!(world, ())
    child = new_entity!(world, (Position(1.1, 1.1), ChildOf() => parent))

    # Raised BoundsError: attempt to access 2-element Vector{Ark._MaskFilter{1}} at index [0]
    remove_entity!(world, parent)
end
