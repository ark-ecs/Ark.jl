
function _entity_order(filter)
    entities = Entity[]
    for (es, _...) in Query(filter)
        append!(entities, es)
    end
    return entities
end

function _position_xs(world, entities)
    return [world[e][Position].x for e in entities]
end

function _velocity_dxs(world, entities)
    return [world[e][Velocity].dx for e in entities]
end

function _healths(world, entities)
    return [world[e][Health].health for e in entities]
end

@testset "sort_entities!" begin
    @testset "basic sort" begin
        world = World(A, B)

        e1 = new_entity!(world, (A(0.0), B(0.0)))
        e2 = new_entity!(world, (A(1.0), B(1.0)))
        e3 = new_entity!(world, (A(2.0), B(2.0)))

        # swap-removes e3 into the first row, so rows are now unsorted
        remove_entity!(world, e1)

        for (entities, as, bs) in Query(filter)
            @test collect(entities) == [e3, e2]
            @test [a.x for a in as] == [2.0, 1.0]
            @test [b.x for b in bs] == [2.0, 1.0]
        end

        filter = Filter(world, (A, B))

        @test sort_entities!(filter) === filter

        for (entities, as, bs) in Query(filter)
            @test collect(entities) == [e2, e3]
            @test [a.x for a in as] == [1.0, 2.0]
            @test [b.x for b in bs] == [1.0, 2.0]
        end

        world = World(Position, Velocity, Health)

        xs = [3.0, -2.0, 5.0, 1.0, 4.0]
        for x in xs
            new_entity!(
                world, (Position(x, 10x), Velocity(x + 100.0, -x), Health(2x)),
            )
        end

        filter = Filter(world, (Position, Velocity, Health))

        by_position_x = entity -> world[entity][Position].x
        @test sort_entities!(filter; by=by_position_x) === filter

        entities = _entity_order(filter)
        sorted_xs = sort(xs)

        @test _position_xs(world, entities) == sorted_xs
        @test _velocity_dxs(world, entities) == sorted_xs .+ 100.0
        @test _healths(world, entities) == 2 .* sorted_xs

        for (row, entity) in enumerate(entities)
            @test world._entities[entity._id] == _EntityIndex(2, row)
        end
    end

    @testset "reverse sort" begin
        world = World(Position, Velocity)

        xs = [1.0, 4.0, 2.0, 5.0, 3.0]
        for x in xs
            new_entity!(world, (Position(x, x), Velocity(-x, x)))
        end

        filter = Filter(world, (Position, Velocity))
        by_position_x = entity -> world[entity][Position].x

        sort_entities!(filter; by=by_position_x, rev=true)

        entities = _entity_order(filter)

        @test _position_xs(world, entities) == sort(xs; rev=true)
        @test _velocity_dxs(world, entities) == -sort(xs; rev=true)
    end

    @testset "sort with custom isless" begin
        world = World(Position, Health)

        hs = [10.0, 5.0, 20.0, 15.0]
        for h in hs
            new_entity!(world, (Position(h, 0.0), Health(h)))
        end

        filter = Filter(world, (Position, Health))

        lt_health_greater = (a, b) -> world[a][Health].health > world[b][Health].health
        sort_entities!(filter; lt=lt_health_greater)

        entities = _entity_order(filter)

        @test _healths(world, entities) == sort(hs; rev=true)
        @test _position_xs(world, entities) == sort(hs; rev=true)
    end

    @testset "sort with registered filters" begin
        world = World(Position, Velocity, Altitude)

        xs = [8.0, 3.0, 5.0, 1.0]
        for x in xs
            new_entity!(world, (Position(x, x), Velocity(x + 1.0, x + 2.0)))
        end

        # non-matching archetype
        new_entity!(world, (Position(100.0, 100.0), Altitude(100.0)))

        filter = Filter(world, (Position, Velocity); register=true)

        by_position_x = entity -> world[entity][Position].x
        sort_entities!(filter; by=by_position_x)

        entities = _entity_order(filter)

        @test _position_xs(world, entities) == sort(xs)
        @test _velocity_dxs(world, entities) == sort(xs) .+ 1.0
        @test count_entities(filter) == length(xs)
    end

    @testset "sort only matching relationship tables" begin
        world = World(Position, Velocity, ChildOf)

        parent1 = new_entity!(world, (Position(0.0, 0.0),))
        parent2 = new_entity!(world, (Position(10.0, 10.0),))

        xs_parent1 = [3.0, 1.0, 2.0]
        for x in xs_parent1
            new_entity!(
                world, (Position(x, x), Velocity(x + 5.0, -x), ChildOf());
                relations=(ChildOf => parent1,),
            )
        end

        xs_parent2 = [9.0, 8.0]
        for x in xs_parent2
            new_entity!(
                world, (Position(x, x), Velocity(x + 10.0, -x), ChildOf());
                relations=(ChildOf => parent2,),
            )
        end

        filter_parent1 = Filter(
            world, (Position, Velocity, ChildOf);
            relations=(ChildOf => parent1,),
        )

        filter_parent2 = Filter(
            world, (Position, Velocity, ChildOf);
            relations=(ChildOf => parent2,),
        )

        by_position_x = entity -> world[entity][Position].x
        sort_entities!(filter_parent1; by=by_position_x)

        entities_parent1 = _entity_order(filter_parent1)
        @test _position_xs(world, entities_parent1) == sort(xs_parent1)
        @test _velocity_dxs(world, entities_parent1) == sort(xs_parent1) .+ 5.0
        @test all(get_relations(world, e, (ChildOf,))[1] == parent1 for e in entities_parent1)

        # The other relationship-target table was not sorted
        entities_parent2 = _entity_order(filter_parent2)
        @test _position_xs(world, entities_parent2) == xs_parent2
        @test all(get_relations(world, e, (ChildOf,))[1] == parent2 for e in entities_parent2)
    end
end
