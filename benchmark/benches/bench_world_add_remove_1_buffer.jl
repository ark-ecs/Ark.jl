
function setup_world_add_remove_1_buffer(n_entities::Int)
    world = World(Position, Velocity)
    buf = CommandBuffer(world, (
        (add_components!, (Velocity,)),
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

    return (entities, world, buf)
end

function benchmark_world_add_remove_1_buffer(args, n)
    entities, world, buf = args
    for e in entities
        add_components!(world, buf, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, buf, e, (Velocity,))
    end
    apply!(world, buf)
end

function setup_world_add_remove_1_buffer_single(n_entities::Int)
    world = World(Position, Velocity)
    buf1 = CommandBuffer(world, (
        (add_components!, (Velocity,)),
    ))
    buf2 = CommandBuffer(world, (
        (remove_components!, (Velocity,)),
    ))

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    for e in entities
        add_components!(world, buf1, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, buf2, e, (Velocity,))
    end
    apply!(world, buf1)
    apply!(world, buf2)

    return (entities, world, buf1, buf2)
end

function benchmark_world_add_remove_1_buffer_single(args, n)
    entities, world, buf1, buf2 = args
    for e in entities
        add_components!(world, buf1, e, (Velocity(0, 0),))
    end
    for e in entities
        remove_components!(world, buf2, e, (Velocity,))
    end
    apply!(world, buf1)
    apply!(world, buf2)
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_1_buffer n=$(n)"] =
        @be setup_world_add_remove_1_buffer($n) benchmark_world_add_remove_1_buffer(_, $n) seconds = SECONDS
    SUITE["benchmark_world_add_remove_1_buffer_single n=$(n)"] =
        @be setup_world_add_remove_1_buffer_single($n) benchmark_world_add_remove_1_buffer_single(_, $n) seconds = SECONDS
end
