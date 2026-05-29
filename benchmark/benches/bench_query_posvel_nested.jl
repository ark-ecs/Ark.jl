function setup_query_create_relation_world(n)
    world = World(Position, Velocity, Relation{ChildOf})
    parents = Vector{Entity}(undef, n)

    for i in 1:n
        parent = new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        @inbounds parents[i] = parent
        new_entity!(world, (Position(0, 0), Velocity(1, 1), ChildOf() => parent))
    end

    return world, parents
end

function setup_query_create_relation(n)
    world, parents = setup_query_create_relation_world(n)
    benchmark_query_create_relation((world, parents), n)
    return world, parents
end

function benchmark_query_create_relation(args, n)
    world, parents = args

    for i in 1:n
        @inbounds parent = parents[i]
        query = Query(world, (Position, Velocity, ChildOf => parent))
        close!(query)
    end

    return world
end

SUITE["benchmark_query_create_relation n=1000"] =
    @be setup_query_create_relation($1000) benchmark_query_create_relation(_, $1000) seconds = SECONDS

function setup_query_create_relation_filter(n)
    world, parents = setup_query_create_relation_world(n)

    first_filter = Filter(world, (Position, Velocity, ChildOf => parents[1]))
    filters = Vector{typeof(first_filter)}(undef, n)
    filters[1] = first_filter
    for i in 2:n
        @inbounds filters[i] = Filter(world, (Position, Velocity, ChildOf => parents[i]))
    end

    benchmark_query_create_relation_filter(filters, n)
    return filters
end

function benchmark_query_create_relation_filter(filters, n)
    for i in 1:n
        @inbounds filter = filters[i]
        query = Query(filter)
        close!(query)
    end

    return filters
end

SUITE["benchmark_query_create_relation_filter n=1000"] =
    @be setup_query_create_relation_filter($1000) benchmark_query_create_relation_filter(_, $1000) seconds = SECONDS
