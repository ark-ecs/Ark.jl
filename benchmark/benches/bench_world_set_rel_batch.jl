
function setup_world_set_rel_batch(n_entities::Int)
    world = World(Position, ChildOf)
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    filter = Filter(world, (ChildOf,))

    for i in 1:n_entities
        new_entity!(world, (ChildOf() => parent1,))
    end

    set_relations!(world, filter, (ChildOf => parent2,))
    set_relations!(world, filter, (ChildOf => parent1,))

    return (filter, world, parent2)
end

function benchmark_world_set_rel_batch(args, n)
    filter, world, parent = args
    set_relations!(world, filter, (ChildOf => parent,))
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_rel_batch n=$(n)"] =
        @be setup_world_set_rel_batch($n) benchmark_world_set_rel_batch(_, $n) evals = 1 seconds = SECONDS
end
