
function setup_world_remove_entities_5(n::Int)
    world = World(Position, Velocity, CompA, CompB, CompC)

    new_entities!(world, n, (Position(0, 0), Velocity(0, 0), CompA(0, 0), CompB(0, 0), CompC(0, 0)))

    # Run once to allocate memory
    filter = Filter(world, (Position, Velocity, CompA, CompB, CompC))
    remove_entities!(world, filter)
    new_entities!(world, n, (Position(0, 0), Velocity(0, 0), CompA(0, 0), CompB(0, 0), CompC(0, 0)))

    return (world, filter)
end

function benchmark_world_remove_entities_5(args, n::Int)
    world, filter = args
    remove_entities!(world, filter)
end

for n in (100, 10_000)
    SUITE["benchmark_world_remove_entities_5 n=$(n)"] =
        @be setup_world_remove_entities_5($n) benchmark_world_remove_entities_5(_, $n) evals = 1 seconds = SECONDS
end
