
function setup_world_set_rel(n_entities::Int)
    world = World(Position, ChildOf)
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (ChildOf(),); relations=(ChildOf => parent1,))
        push!(entities, e)
    end

    for e in entities
        set_relations!(world, e, (ChildOf => parent2,))
    end

    for e in entities
        set_relations!(world, e, (ChildOf => parent1,))
    end

    return (entities, world, parent2)
end

function benchmark_world_set_rel(args, n)
    entities, world, parent = args
    for e in entities
        set_relations!(world, e, (ChildOf => parent,))
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_rel n=$(n)"] =
        @be setup_world_set_rel($n) benchmark_world_set_rel(_, $n) evals = 1 seconds = SECONDS
end
