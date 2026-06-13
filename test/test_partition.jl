
@testset "partition_entities!" begin
    @testset "basic tests" begin
        for register in (true, false)
            world = World(Position, Velocity)
            new_entity!(world, (Position(0.0, 0.0),))
            partition_entities!(world, Filter(world, (Position,); register); pred=e -> true)

            world = World(Position, Velocity)

            xs = [3.0, -2.0, 5.0, 1.0, 4.0]
            for i in eachindex(xs)
                new_entity!(world, (Position(xs[i], xs[i]), Velocity(xs[i], xs[i])))
            end

            filter = Filter(world, (Position, Velocity); register)

            # Predicate to select which entities go first
            less_than_3 = e -> world[e][Position].x < 3.0

            @test filter === partition_entities!(world, filter; pred=less_than_3)

            entities_in_order = Entity[]
            for (es, positions, _) in Query(world, filter)
                append!(entities_in_order, es)
            end

            partitioned_xs = [world[e][Position].x for e in entities_in_order]

            # Entities with x < 3.0 should come first
            @test all(partitioned_xs[1:2] .< 3.0)
            @test all(partitioned_xs[3:5] .>= 3.0)
        end
    end

    @testset "partition preserves entity data" begin
        world = World(Position, Velocity)

        original_xs = Float64[]
        for i in 1:10
            new_entity!(world, (Position(i, i), Velocity(i, i)))
            push!(original_xs, Float64(i))
        end

        filter = Filter(world, (Position, Velocity))

        partition_entities!(world, filter; pred=e -> world[e][Position].x < 5.0)

        all_xs = Float64[]
        for (entities, positions, _) in Query(world, filter)
            for p in positions
                push!(all_xs, p.x)
            end
        end
        @test sort(original_xs) == sort(all_xs)
    end

    @testset "partition only works on matching archetypes" begin
        world = World(Position, Velocity, Altitude)

        for i in 1:4
            new_entity!(world, (Position(10.0 + i, 10.0 + i),))
        end

        for i in 1:5
            new_entity!(world, (Position(10.0 + i, 10.0 + i), Velocity(i, i)))
        end

        filter = Filter(world, (Position, Velocity))

        partition_entities!(world, filter; pred=e -> world[e][Position].x > 13.0)

        # Verify entities with only Position are unchanged
        pos_only_filter = Filter(world, (Position,); without=(Velocity,))
        for (entities, positions) in Query(world, pos_only_filter)
            @test [p.x for p in positions] == [11.0, 12.0, 13.0, 14.0]
        end

        # Verify entities with Position and Velocity are partitioned
        for (entities, positions, _) in Query(world, filter)
            @test length(entities) == 5
            partitioned_xs = [p.x for p in positions]
            @test all(partitioned_xs[1:2] .> 13.0)
            @test all(partitioned_xs[3:5] .<= 13.0)
        end
    end
end
