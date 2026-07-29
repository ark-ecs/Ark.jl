
function setup_resource()
    world = World(Position, Velocity)
    add_resource!(world, Tick(0))
    return world
end

function benchmark_resource(args)
    world = args
    res = get_resource(world, Tick)
    res.time += 1
    return world
end

SUITE["benchmark_world_resource n=1"] = @be setup_resource() benchmark_resource(_) seconds = SECONDS
