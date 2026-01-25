
function setup_world_add_remove_1(n_entities::Int)
    world = World(Position, Velocity)

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

function benchmark_world_add_remove_1(args, n)
    entities, world = args
    for e in entities
        add_components!(world, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, e, (Velocity,))
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_1 n=$(n)"] =
        @be setup_world_add_remove_1($n) benchmark_world_add_remove_1(_, $n) seconds = SECONDS
end
