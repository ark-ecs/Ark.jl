
function setup_query_posvel_32_arch(n_entities::Int)
    world = World(
        Position, Velocity,
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5};
        initial_capacity=clamp(nextpow(2, div(n_entities, 32) + 1), 32, 1024),
    )

    pos = Position(0, 0)
    vel = Velocity(1, 1)
    all_comps = (
        CompN{1}(0, 0),
        CompN{2}(0, 0),
        CompN{3}(0, 0),
        CompN{4}(0, 0),
        CompN{5}(0, 0),
    )

    # TODO: make this faster by using batches
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
    expected_archetypes = min(n_entities + 1, 33)
    world_state = Ark._state(world)
    num_archetypes = length(world_state._archetypes)
    if num_archetypes != expected_archetypes
        error("expected $expected_archetypes archetypes, got $num_archetypes")
    end

    filter = Filter(world, (Position, Velocity))

    sum = 0
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
        sum += length(pos_column) + length(vel_column)
    end
    return world, filter, sum
end

function setup_query_posvel_1k_arch(n_entities::Int, register::Bool)
    world = World(
        Position, Velocity,
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10};
        initial_capacity=clamp(nextpow(2, div(n_entities, 1000) + 1), 32, 1024),
    )

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

    # TODO: make this faster by using batches
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
    world_state = Ark._state(world)
    num_archetypes = length(world_state._archetypes)
    if num_archetypes != expected_archetypes
        error("expected $expected_archetypes archetypes, got $num_archetypes")
    end

    filter = Filter(world, (Position, Velocity); register=register)

    sum = 0
    if register
        for (_, pos_column, vel_column) in Query(world, filter)
            for i in eachindex(pos_column)
                @inbounds pos = pos_column[i]
                @inbounds vel = vel_column[i]
                @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
            end
            sum += length(pos_column) + length(vel_column)
        end
    else
        for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
            for i in eachindex(pos_column)
                @inbounds pos = pos_column[i]
                @inbounds vel = vel_column[i]
                @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
            end
            sum += length(pos_column) + length(vel_column)
        end
    end
    return world, filter, sum
end

function benchmark_query_posvel_many_arch(args, n)
    world, _, _ = args
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
    return world
end

function benchmark_query_posvel_many_arch_cached(args, n)
    world, filter, _ = args
    for (_, pos_column, vel_column) in Query(world, filter)
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
    return world
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_32_arch n=$(n)"] =
        @be setup_query_posvel_32_arch($n) benchmark_query_posvel_many_arch(_, $n) evals = 100 seconds =
            SECONDS
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_1k_arch n=$(n)"] =
        @be setup_query_posvel_1k_arch($n, $(false)) benchmark_query_posvel_many_arch(_, $n) evals = 100 seconds =
            SECONDS
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_1k_arch_cached n=$(n)"] =
        @be setup_query_posvel_1k_arch($n, $(true)) benchmark_query_posvel_many_arch_cached(_, $n) evals = 100 seconds =
            SECONDS
end
