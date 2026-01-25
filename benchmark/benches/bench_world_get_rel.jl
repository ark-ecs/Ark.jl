
function setup_world_get_rel(n_entities::Int)
    world = World(Position, ChildOf)
    parent = new_entity!(world, ())

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (ChildOf(),); relations=(ChildOf => parent,))
        push!(entities, e)
    end

    sum = 0.0
    for e in entities
        p, = get_relations(world, e, (ChildOf,))
        sum += p._id
    end
    sum

    return (entities, world)
end

function benchmark_world_get_rel(args, n)
    entities, world = args
    sum = 0.0
    for e in entities
        p, = get_relations(world, e, (ChildOf,); unchecked=true)
        sum += p._id
    end
    return sum
end

for n in (100, 10_000)
    SUITE["benchmark_world_get_rel n=$(n)"] =
        @be setup_world_get_rel($n) benchmark_world_get_rel(_, $n) evals = 100 seconds = SECONDS
end
