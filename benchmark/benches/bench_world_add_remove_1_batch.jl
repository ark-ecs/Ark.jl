
function setup_world_add_remove_1_batch(n_entities::Int)
    world = World(Position, Velocity)

    filter = Filter(world, (Position,))

    for i in 1:n_entities
        new_entity!(world, (Position(i, i * 2),))
    end

    add_components!(world, filter, (Velocity(0, 0),))
    remove_components!(world, filter, (Velocity,))

    return (filter, world)
end

function benchmark_world_add_remove_1_batch(args, n)
    filter, world = args
    add_components!(world, filter, (Velocity(0, 0),))
    remove_components!(world, filter, (Velocity,))
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_1_batch n=$(n)"] =
        @be setup_world_add_remove_1_batch($n) benchmark_world_add_remove_1_batch(_, $n) seconds = SECONDS
end
