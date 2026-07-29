
function setup_query_create(n)
    world = World(Position, Velocity)

    for i in 1:n
        query = Query(world, (Position, Velocity))
        close!(query)
    end

    return world
end

function benchmark_query_create(args, n)
    world = args

    for i in 1:n
        query = Query(world, (Position, Velocity))
        close!(query)
    end

    return world
end

SUITE["benchmark_query_create n=1000"] =
    @be setup_query_create($1000) benchmark_query_create(_, $1000) seconds = SECONDS

function setup_query_create_filter(n)
    world = World(Position, Velocity)

    filter = Filter(world, (Position, Velocity))
    for i in 1:n
        query = Query(world, filter)
        close!(query)
    end

    return world
end

function benchmark_query_create_filter(args, n)
    world = args

    filter = Filter(world, (Position, Velocity))
    for i in 1:n
        query = Query(world, filter)
        close!(query)
    end

    return world
end

SUITE["benchmark_query_create_filter n=1000"] =
    @be setup_query_create_filter($1000) benchmark_query_create_filter(_, $1000) seconds = SECONDS
