
function setup_query_posvel_soa(n_entities::Int)
    world = World(
        Position => Storage{StructArray},
        Velocity => Storage{StructArray},
    )
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
    end
    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        for i in eachindex(pos_column)
            @inbounds pos = pos_column[i]
            @inbounds vel = vel_column[i]
            @inbounds pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
    return world
end

function benchmark_query_posvel_soa(args, n)
    world = args
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
    SUITE["benchmark_query_posvel_soa n=$(n)"] =
        @be setup_query_posvel_soa($n) benchmark_query_posvel_soa(_, $n) evals = 100 seconds = SECONDS
end
