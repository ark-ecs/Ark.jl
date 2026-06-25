function setup_query_readonly(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2), Velocity(i * 0.5, i * 0.25)))
    end
    return world
end

function benchmark_query_readonly(world, n)
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

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_readonly n=$(n)"] =
        @be setup_query_readonly($n) benchmark_query_readonly(_, $n) evals = 100 seconds = SECONDS
end
