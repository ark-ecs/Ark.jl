
function setup_world_add_remove_1_buffer(n_entities::Int)
    world = World(Position, Velocity)
    buf = CommandBuffer(world, (
        (add_components!, (Velocity(0, 0),)),
        (remove_components!, (Velocity,)),
    ))

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    for e in entities
        add_components!(world, buf, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, buf, e, (Velocity,))
    end
    apply!(world, buf)

    return (entities, world)
end

function benchmark_world_add_remove_1_buffer(args, n)
    entities, world = args
    buf = CommandBuffer(world, (
        (add_components!, (Velocity(0, 0),)),
        (remove_components!, (Velocity,)),
    ))
    for e in entities
        add_components!(world, buf, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, buf, e, (Velocity,))
    end
    apply!(world, buf)
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_1_buffer n=$(n)"] =
        @be setup_world_add_remove_1_buffer($n) benchmark_world_add_remove_1_buffer(_, $n) seconds = SECONDS
end
