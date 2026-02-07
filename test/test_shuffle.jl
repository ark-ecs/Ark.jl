
using Random

@testset "Shuffle" begin
    @testset "Basic Shuffle" begin
        world = World(Position, Velocity)
        N = 100
        ids = Vector{Entity}(undef, N)
        for i in 1:N
            ids[i] = new_entity!(world, (Position(i, i), Velocity(i, i)))
        end

        f = Filter(world, (Position, Velocity))

        pos_before = Vector{Position}(undef, length(ids))
        for (i, id) in enumerate(ids)
            p, = get_components(world, id, (Position,))
            pos_before[i] = p
        end

        Random.seed!(1234)
        shuffle!(f)
        pos_after = Vector{Position}(undef, length(ids))
        for (i, id) in enumerate(ids)
            p, = get_components(world, id, (Position,))
            pos_after[i] = p
        end
        @test pos_before == pos_after
        
        values_in_order = []
        for (entities, positions, velocities) in Query(f)
            for (p, v) in zip(positions, velocities)
                push!(values_in_order, (p, v))
            end
        end
        
        expected_values_sorted = [(Position(i, i), Velocity(i, i)) for i in 1:N]
        @test sort(values_in_order, by=p->p.x) == expected_values_sorted
        @test values_in_order != expected_values_sorted
    end

    @testset "Relations Shuffle" begin
        world = World(Position, ChildOf)
        
        parents = [new_entity!(world, (Position(i, i),)) for i in 1:100]
        children = [new_entity!(world, (Position(i, i), ChildOf()); relations=(ChildOf => parents[i],)) for i in 1:100]
        
        f_parents = Filter(world, (Position,); without=(ChildOf,))
        shuffle!(f_parents)
        
        for i in 1:100
             child = children[i]
             target, = get_relations(world, child, (ChildOf,))
             @test target == parents[i]
        end
        
        f_children = Filter(world, (ChildOf,))
        shuffle!(f_children)
        
        for i in 1:100
             child = children[i]
             target, = get_relations(world, child, (ChildOf,))
             @test target == parents[i]
             
             pos, = get_components(world, child, (Position,))
             @test pos == Position(i, i)
        end
    end
end
