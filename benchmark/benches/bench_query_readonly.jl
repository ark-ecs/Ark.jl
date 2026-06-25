function setup_query_readonly(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(i * 0.5, i * 0.25)))
    end
    return world
end

function benchmark_query_posvel_mean_readonly(world, n)
    x_sum = 0.0
    y_sum = 0.0
    dx_sum = 0.0
    dy_sum = 0.0
    count = 0

    for (_, pos_column, vel_column) in Query(world, (Const{Position}, Const{Velocity}))
        @inbounds for i in eachindex(pos_column, vel_column)
            pos = pos_column[i]
            vel = vel_column[i]
            x_sum += pos.x
            y_sum += pos.y
            dx_sum += vel.dx
            dy_sum += vel.dy
            count += 1
        end
    end

    inv_count = inv(count)
    return Position(x_sum * inv_count, y_sum * inv_count),
           Velocity(dx_sum * inv_count, dy_sum * inv_count)
end

function benchmark_query_posvel_mean(world, n)
    x_sum = 0.0
    y_sum = 0.0
    dx_sum = 0.0
    dy_sum = 0.0
    count = 0

    for (_, pos_column, vel_column) in Query(world, (Position, Velocity))
        @inbounds for i in eachindex(pos_column, vel_column)
            pos = pos_column[i]
            vel = vel_column[i]
            x_sum += pos.x
            y_sum += pos.y
            dx_sum += vel.dx
            dy_sum += vel.dy
            count += 1
        end
    end

    inv_count = inv(count)
    return Position(x_sum * inv_count, y_sum * inv_count),
           Velocity(dx_sum * inv_count, dy_sum * inv_count)
end

for n in (100, 100_000)
    SUITE["benchmark_query_posvel_mean n=$(n)"] =
        @be setup_query_readonly($n) benchmark_query_posvel_mean(_, $n) evals = 100 seconds = SECONDS
    SUITE["benchmark_query_posvel_mean_readonly n=$(n)"] =
        @be setup_query_readonly($n) benchmark_query_posvel_mean_readonly(_, $n) evals = 100 seconds = SECONDS
end
