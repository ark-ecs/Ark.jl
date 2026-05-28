
function setup_query_posvel_nested(n_entities::Int)

    n_parents = div(n_entities, 100)

    world = World(
        Position,
        Velocity,
        Relation{ChildOf};
    )
    parents = Vector{Entity}(undef, n_parents)

    for i in 1:n_parents
        parent = new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        parents[i] = parent
        new_entities!(
            world,
            100,
            (Position(0, 0), Velocity(1, 1), ChildOf() => parent),
        )
    end

    parent_filter = Filter(world, (Position, Velocity); without=(ChildOf,))
    first_child_filter = Filter(world, (Position, Velocity, ChildOf => parents[1]))
    child_filters = Vector{typeof(first_child_filter)}(undef, n_parents)
    child_filters[1] = first_child_filter
    for i in 2:n_parents
        child_filters[i] = Filter(world, (Position, Velocity, ChildOf => parents[i]))
    end

    sum = benchmark_query_posvel_nested((world, parent_filter, child_filters, 0), n_entities)
    if sum != n_entities
        error("expected $n_entities child iterations, got $sum")
    end

    return world, parent_filter, child_filters, sum
end

function benchmark_query_posvel_nested(args, n)
    _, parent_filter, child_filters, _ = args
    sum = 0
    parent_index = 1

    for (_, parent_pos_column, parent_vel_column) in Query(parent_filter)
        for parent_i in eachindex(parent_pos_column)
            @inbounds child_filter = child_filters[parent_index]
            for (_, child_pos_column, child_vel_column, _) in Query(child_filter)
                for child_i in eachindex(child_pos_column)
                    @inbounds pos = child_pos_column[child_i]
                    @inbounds vel = child_vel_column[child_i]
                    @inbounds child_pos_column[child_i] = Position(pos.x + vel.dx, pos.y + vel.dy)
                    sum += 1
                end
            end

            @inbounds pos = parent_pos_column[parent_i]
            @inbounds vel = parent_vel_column[parent_i]
            @inbounds parent_pos_column[parent_i] = Position(pos.x + vel.dx, pos.y + vel.dy)
            parent_index += 1
        end
    end

    return sum
end

for n in (100, 10_000)
    SUITE["benchmark_query_posvel_nested n=$(n)"] =
        @be setup_query_posvel_nested($n) benchmark_query_posvel_nested(_, $n) evals = 1 seconds = SECONDS
end
