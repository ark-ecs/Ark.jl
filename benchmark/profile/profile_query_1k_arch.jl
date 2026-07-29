using Ark
using Printf
using Profile
using StatProfilerHTML

include("BenchTypes.jl")

function setup_query_1k_arch()
    n_entities = 1024

    world = World(
        Position, Velocity,
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10};
        initial_capacity=8,
    )

    println("setup")

    pos = Position(0, 0)
    vel = Velocity(1, 1)
    all_comps = (
        CompN{1}(0, 0),
        CompN{2}(0, 0),
        CompN{3}(0, 0),
        CompN{4}(0, 0),
        CompN{5}(0, 0),
        CompN{6}(0, 0),
        CompN{7}(0, 0),
        CompN{8}(0, 0),
        CompN{9}(0, 0),
        CompN{10}(0, 0),
    )

    comps = Any[]
    for i in 1:n_entities
        push!(comps, pos, vel)
        for (j, comp) in enumerate(all_comps)
            m = 1 << (j - 1)
            if i & m == m
                push!(comps, comp)
            end
        end
        new_entity!(world, (comps...,))
        resize!(comps, 0)
    end
    expected_archetypes = min(n_entities + 1, 1025)
    num_archetypes = length(world._archetypes)
    if num_archetypes != expected_archetypes
        error("expected $expected_archetypes archetypes, got $num_archetypes")
    end

    return world
end

function run_query_1k_arch(world::World)
    println("run")
    iters = 100_000

    for i in 1:iters
        for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
            for i in eachindex(pos_column)
                @inbounds pos = pos_column[i]
                @inbounds vel = vel_column[i]
                @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
            end
        end
    end

    return world
end

function profile_query_1k_arch()
    world = setup_query_1k_arch()
    run_query_1k_arch(world)
end

Profile.clear()
profile_query_1k_arch()
@profilehtml profile_query_1k_arch()
