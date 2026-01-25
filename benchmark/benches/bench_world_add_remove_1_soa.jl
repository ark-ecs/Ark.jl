
function setup_world_add_remove_1_soa(n_entities::Int)
    world = World(
        Position => Storage{StructArray},
        Velocity => Storage{StructArray},
    )

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    for e in entities
        add_components!(world, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, e, (Velocity,))
    end

    return (entities, world)
end

function benchmark_world_add_remove_1_soa(args, n)
    entities, world = args
    for e in entities
        add_components!(world, e, (Velocity(0, 0),); unchecked=true)
    end
    for e in entities
        remove_components!(world, e, (Velocity,); unchecked=true)
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_1_soa n=$(n)"] =
        @be setup_world_add_remove_1_soa($n) benchmark_world_add_remove_1_soa(_, $n) seconds = SECONDS
end
