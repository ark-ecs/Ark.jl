
@testset "Relations remove target" begin
    world = World(Position, Relation{ChildOf}, Relation{ChildOf2})

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    new_entities!(world, 100, (Position, ChildOf => parent1)) do (_, positions, children)
        for i in eachindex(positions, children)
            positions[i] = Position(i, i)
            children[i] = ChildOf()
        end
    end

    new_entities!(world, 50, (Position, ChildOf => parent2)) do (_, positions, children)
        for i in eachindex(positions, children)
            positions[i] = Position(i, i)
            children[i] = ChildOf()
        end
    end

    counters = Int[0, 0]
    obs1 = observe!(world, OnAddRelations) do entity
        @test get_relations(world, entity, (ChildOf,)) == (zero_entity,)
        counters[1] += 1
    end
    obs2 = observe!(world, OnRemoveRelations) do entity
        rel = get_relations(world, entity, (ChildOf,))
        @test rel == (parent1,) || rel == (parent2,)
        counters[2] += 1
    end

    tables = 0
    count = 0
    for (_, children) in Query(world, (ChildOf,))
        tables += 1
        count += length(children)
    end
    @test tables == 2
    @test count == 150

    remove_entity!(world, parent1)
    @test counters == [100, 100]

    count = 0
    for (_, children) in Query(world, (ChildOf => zero_entity,))
        count += length(children)
    end
    @test count == 100

    remove_entity!(world, parent2)
    @test counters == [150, 150]

    unregister!(world, obs1)
    unregister!(world, obs2)

    count = 0
    for (_, children) in Query(world, (ChildOf => zero_entity,))
        count += length(children)
    end
    @test count == 150

    @test length(_state(world)._tables) == 4

    count = 0
    for (ents,) in Query(world, (); with=(ChildOf => zero_entity,))
        @test typeof(ents) == Entities
        count += length(ents)
    end
    @test count == 150

    @test length(_state(world)._tables) == 4

    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())
    e1 = new_entity!(world, (Position(0, 0), ChildOf() => parent3))
    e2 = new_entity!(world, (Position(0, 0), ChildOf() => parent4))
    @test length(_state(world)._tables) == 4

    parents = get_relations(world, e1, (ChildOf,))
    @test parents == (parent3,)
    parents = get_relations(world, e2, (ChildOf,))
    @test parents == (parent4,)
end

@testset "Relations multiple" begin
    world = World(Position, Relation{ChildOf}, Relation{ChildOf2})

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())

    new_entities!(world, 50, (Position, ChildOf => parent1, ChildOf2 => parent2)) do (_, positions, children, children2)
        for i in eachindex(positions, children, children2)
            positions[i] = Position(i, i)
            children[i] = ChildOf()
            children2[i] = ChildOf2()
        end
    end

    new_entities!(world, 30, (Position, ChildOf => parent2, ChildOf2 => parent3)) do (_, positions, children, children2)
        for i in eachindex(positions, children, children2)
            positions[i] = Position(i, i)
            children[i] = ChildOf()
            children2[i] = ChildOf2()
        end
    end

    @test count_entities(world, Filter(world, (ChildOf, ChildOf2))) == 80

    cnt = 0
    for (entities, _) in Query(world, (ChildOf => parent1,))
        cnt += length(entities)
    end
    @test cnt == 50

    cnt = 0
    for (entities, _) in Query(world, (ChildOf2 => parent2,))
        cnt += length(entities)
    end
    @test cnt == 50

    cnt = 0
    for (entities, _, _) in Query(world, (ChildOf => parent2, ChildOf2 => parent3))
        cnt += length(entities)
    end
    @test cnt == 30

    cnt = 0
    for (entities, _, _) in Query(world, (ChildOf => parent1, ChildOf2 => parent3))
        cnt += length(entities)
    end
    @test cnt == 0

    add_counters = [0, 0]
    remove_counters = [0, 0]

    obs1 = observe!(world, OnAddRelations, (ChildOf,)) do entity
        add_counters[1] += 1
    end
    obs2 = observe!(world, OnAddRelations, (ChildOf2,)) do entity
        add_counters[2] += 1
    end
    obs3 = observe!(world, OnRemoveRelations, (ChildOf,)) do entity
        remove_counters[1] += 1
    end
    obs4 = observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        remove_counters[2] += 1
    end

    remove_entity!(world, parent1)
    @test add_counters == [50, 0]
    @test remove_counters == [50, 0]

    cnt = 0
    for (entities, _) in Query(world, (ChildOf => zero_entity,))
        cnt += length(entities)
    end
    @test cnt == 50

    cnt = 0
    for (entities, _) in Query(world, (ChildOf2 => parent2,))
        cnt += length(entities)
    end
    @test cnt == 50

    remove_entity!(world, parent2)
    @test add_counters == [80, 50]
    @test remove_counters == [80, 50]

    cnt = 0
    for (entities, _) in Query(world, (ChildOf => zero_entity,))
        cnt += length(entities)
    end
    @test cnt == 80

    cnt = 0
    for (entities, _) in Query(world, (ChildOf2 => zero_entity,))
        cnt += length(entities)
    end
    @test cnt == 50

    cnt = 0
    for (entities, _) in Query(world, (ChildOf2 => parent3,))
        cnt += length(entities)
    end
    @test cnt == 30

    e = new_entity!(world, (Position(0, 0), ChildOf() => parent3, ChildOf2() => parent3))
    @test get_relations(world, e, (ChildOf, ChildOf2)) == (parent3, parent3)

    parent4 = new_entity!(world, ())
    set_relations!(world, e, (ChildOf => parent4, ChildOf2 => parent4))
    @test get_relations(world, e, (ChildOf, ChildOf2)) == (parent4, parent4)
end

@testset "Relation rejected for stale entity with recycled id" begin
    world = World(Position, Relation{ChildOf})

    old_parent = new_entity!(world, (Position(0.0, 0.0),))
    child = new_entity!(world, (ChildOf() => old_parent,))

    remove_entity!(world, old_parent)
    @test !is_alive(world, old_parent)

    new_parent = new_entity!(world, (Position(1.0, 1.0),))
    @test old_parent._id == new_parent._id
    @test old_parent != new_parent
    @test is_alive(world, new_parent)

    set_relations!(world, child, (ChildOf => new_parent,))
    @test get_relations(world, child, (ChildOf,)) == (new_parent,)
    @test_throws ArgumentError set_relations!(world, child, (ChildOf => old_parent,))

    world = World(Position, Relation{ChildOf})

    old_parent = new_entity!(world, (Position(0.0, 0.0),))
    remove_entity!(world, old_parent)
    new_parent = new_entity!(world, (Position(1.0, 1.0),))

    new_entity!(world, (ChildOf() => new_parent,))
    @test_throws ArgumentError new_entity!(world, (ChildOf() => old_parent,))
end

@testset "Issue #477" begin
    world = World(Relation{ChildOf})

    parent = new_entity!(world, ())
    child = new_entity!(world, (ChildOf() => parent,))

    remove_entity!(world, parent)
    @test get_relations(world, child, (ChildOf,)) == (zero_entity,)
    @test length(_state(world)._archetypes[2].tables) == 1
    @test length(_state(world)._archetypes[2].free_tables) == 1

    ghost = new_entity!(world, (ChildOf() => child,))
    @test is_alive(world, ghost) == true
    @test has_components(world, ghost, (ChildOf,)) == true

    @test get_relations(world, child, (ChildOf,)) == (zero_entity,)
    @test get_relations(world, ghost, (ChildOf,)) == (child,)
    @test length(_state(world)._archetypes[2].tables) == 2
    @test length(_state(world)._archetypes[2].free_tables) == 0

    query = Query(world, (ChildOf,))
    @test count_entities(world, query) == 2
    @test count_tables(world, query) == 2

    cnt = 0
    for (entities,) in Query(world, (ChildOf,))
        cnt += length(entities)
    end
    @test cnt == 2
end

@testset "Filter incorrect targets Issue #497" begin
    world = World(Relation{ChildOf})

    t1 = new_entity!(world, ())
    filter_t1 = Filter(world, (ChildOf => t1,))
    remove_entity!(world, t1)

    t2 = new_entity!(world, ())
    c2 = new_entity!(world, (ChildOf() => t2,))

    @test length(_state(world)._archetypes) == 2
    @test length(_state(world)._tables) == 2

    @test length(_state(world)._archetypes[2].tables) == 1
    @test length(_state(world)._archetypes[2].free_tables) == 0

    matches = Entity[]
    for (entities, _) in Query(world, filter_t1)
        for e in entities
            push!(matches, e)
        end
    end

    @test isempty(matches) == true
end

@testset "Cleanup error Issue #498" begin
    world = World(Position, Relation{ChildOf})
    observe!(world, OnRemoveEntity) do entity
        nothing
    end
    parent = new_entity!(world, (Position(0.0, 0.0),))
    child = new_entity!(world, (Position(1.1, 1.1), ChildOf() => parent))

    # This raised an error due to locked world
    remove_entities!(world, Filter(world, (Position,); without=(ChildOf,)))
end

@testset "Remove entities Issue #606" begin
    struct Tag end
    struct R1 end
    struct R2 end

    world = World(Tag, Relation{R1}, Relation{R2})

    p1 = new_entity!(world, (Tag(),))
    p2 = new_entity!(world, (Tag(),))

    child = new_entity!(world, (R1() => p1, R2() => p2))
    @test get_relations(world, child, (R1, R2)) == (p1, p2)

    # Before the fix in PR #611, this panicked with:
    # "ArgumentError: can't use a dead entity as relation target, except for the zero entity"
    remove_entities!(world, Filter(world, (Tag,)))

    @test is_alive(world, p1) == false
    @test is_alive(world, p2) == false
    @test get_relations(world, child, (R1, R2)) == (zero_entity, zero_entity)
end
