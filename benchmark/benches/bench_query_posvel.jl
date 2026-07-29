
function setup_query_posvel_hot(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
    end
    sum = 0
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
        sum += length(pos_column) + length(vel_column)
    end
    return world, sum
end

function setup_query_posvel_cold(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
    end
    sum = 0
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        sum += length(pos_column) + length(vel_column)
    end
    return world, sum
end

function benchmark_query_posvel(args, n)
    world, _ = args
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
    return world
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_hot n=$(n)"] =
        @be setup_query_posvel_hot($n) benchmark_query_posvel(_, $n) evals = 100 seconds = SECONDS
end
for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_cold n=$(n)"] =
        @be setup_query_posvel_cold($n) benchmark_query_posvel(_, $n) evals = 1 seconds = SECONDS
end
