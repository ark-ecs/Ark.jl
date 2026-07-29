
function setup_query_posvel_fields(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
    end
    for columns in Query(world, (Position, Velocity))
        @unpack _, (x, y), (dx, dy) = columns
        @inbounds x .+= dx
        @inbounds y .+= dy
    end
    return world
end

function benchmark_query_posvel_fields(args, n)
    world = args
    for columns in Query(world, (Position, Velocity))
        @unpack _, (x, y), (dx, dy) = columns
        @inbounds for i in eachindex(x, y, dx, dy)
            x[i] += dx[i]
            y[i] += dy[i]
        end
    end
    return world
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_fields n=$(n)"] =
        @be setup_query_posvel_fields($n) benchmark_query_posvel_fields(_, $n) evals = 100 seconds =
            SECONDS
end

function benchmark_query_posvel_fields_broadcast(args, n)
    world = args
    for columns in Query(world, (Position, Velocity))
        @unpack _, (x, y), (dx, dy) = columns
        @inbounds x .+= dx
        @inbounds y .+= dy
    end
    return world
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_fields_broadcast n=$(n)"] =
        @be setup_query_posvel_fields($n) benchmark_query_posvel_fields_broadcast(_, $n) evals = 100 seconds =
            SECONDS
end
