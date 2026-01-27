
using DifferentiationInterface
using Mooncake
using Random

@testset "Compute gradients through Mooncake.jl" begin
    function run_world(args)
        alpha, beta = args
        world = World(Position, Velocity)

        entities = Entity[]
        sizehint!(entities, 100)
        for i in 1:100
            entity = new_entity!(world, (Position(i, i * 2),))
            push!(entities, entity)
        end

        for e in entities
            add_components!(world, e, (Velocity(1, 1),))
        end

        for i in 1:10
            for (entities, positions, velocities) in Query(world, (Position, Velocity))
                @inbounds for i in eachindex(entities)
                    pos = positions[i]
                    vel = velocities[i]
                    positions[i] = Position(alpha * (pos.x + vel.dx), beta * (pos.y + vel.dy))
                end
            end
        end

        all_positions = Position[]
        for (entities, positions) in Query(world, (Position,))
            append!(all_positions, positions)
        end

        return sum(pos.x + pos.y for pos in all_positions)
    end

    for backend in (AutoMooncake(), AutoMooncakeForward())
        g = gradient(run_world, backend, [0.1, 0.5])
        d_alpha, d_beta = g
    
        @test 0.99 < (run_world((0.1 + 10e-5, 0.5)) - run_world((0.1, 0.5))) / (d_alpha * 10e-5) < 1.01
        @test 0.99 < (run_world((0.1, 0.5 + 10e-5)) - run_world((0.1, 0.5))) / (d_beta * 10e-5) < 1.01
    end
end
