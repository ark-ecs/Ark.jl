
using Random

@testset "Basic Shuffle" begin
    for register in (false, true)
        world = World(Position, Velocity => Storage{StructArray})
        N = 100
        ids = Vector{Entity}(undef, N)
        for i in 1:N
            ids[i] = new_entity!(world, (Position(i, i), Velocity(i, i)))
        end

        e = new_entity!(world, (Position(1, 1),))
        remove_entity!(world, e)

        f = Filter(world, (Position,); optional=(Velocity,), register=register)

        pos_before = Vector{Position}(undef, length(ids))
        for (i, id) in enumerate(ids)
            p, = get_components(world, id, (Position,))
            pos_before[i] = p
        end

        Random.seed!(1234)
        shuffle_entities!(f)
        pos_after = Vector{Position}(undef, length(ids))
        for (i, id) in enumerate(ids)
            p, = get_components(world, id, (Position,))
            pos_after[i] = p
        end
        @test pos_before == pos_after

        values_in_order = []
        for (entities, positions, velocities) in Query(f)
            isempty(positions) && continue
            for (p, v) in zip(positions, velocities)
                push!(values_in_order, (p, v))
            end
        end

        expected_values_sorted = [(Position(i, i), Velocity(i, i)) for i in 1:N]
        @test sort(values_in_order, by=pv -> pv[1].x) == expected_values_sorted
        @test values_in_order != expected_values_sorted
    end
end

@testset "Relations Shuffle" begin
    for register in (false, true)
        world = World(Position, ChildOf)

        parents = [new_entity!(world, (Position(i, i),)) for i in 1:100]
        children = [new_entity!(world, (Position(i, i), ChildOf()); relations=(ChildOf => parents[i],)) for i in 1:100]

        child = new_entity!(world, (ChildOf(),); relations=(ChildOf => parents[1],))
        remove_entity!(world, child)

        f_parents = Filter(world, (Position,); without=(ChildOf,), register=register)
        shuffle_entities!(f_parents)

        for i in 1:100
            child = children[i]
            target, = get_relations(world, child, (ChildOf,))
            @test target == parents[i]
        end

        f_children = Filter(world, (ChildOf,); register=register)
        shuffle_entities!(f_children)

        for i in 1:100
            child = children[i]
            target, = get_relations(world, child, (ChildOf,))
            @test target == parents[i]

            pos, = get_components(world, child, (Position,))
            @test pos == Position(i, i)
        end

        reset!(world)
        shuffle_entities!(f)
    end
end
