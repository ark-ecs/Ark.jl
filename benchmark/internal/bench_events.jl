function setup_event_no_obs(n::Int)
    reg = EventRegistry()
    evt = new_event_type!(reg, :Event)

    world = World(Position; mode=MODE)

    entities = Entity[]
    for _ in 1:n
        push!(entities, new_entity!(world, (Position(0, 0),)))
    end

    return world, entities, evt
end

function benchmark_event_no_obs(args, n)
    world, entities, evt = args
    for entity in entities
        emit_event!(world, evt, entity, (Position,))
    end
    world
end

SUITE["benchmark_event_no_obs n=1000"] = @be setup_event_no_obs(1000) benchmark_event_no_obs(_, 1000) seconds = SECONDS

function setup_event_no_match(n::Int)
    reg = EventRegistry()
    evt = new_event_type!(reg, :Event)

    world = World(Position, Velocity)

    entities = Entity[]
    for _ in 1:n
        push!(entities, new_entity!(world, (Position(0, 0),)))
    end

    observe!(world, evt, (Velocity,)) do entity
    end

    return world, entities, evt
end

function benchmark_event_no_match(args, n)
    world, entities, evt = args
    for entity in entities
        emit_event!(world, evt, entity, (Position,))
    end
    world
end

SUITE["benchmark_event_no_match n=1000"] =
    @be setup_event_no_match(1000) benchmark_event_no_match(_, 1000) seconds = SECONDS

function setup_event_match_1(n::Int)
    reg = EventRegistry()
    evt = new_event_type!(reg, :Event)

    world = World(Position, Velocity)

    entities = Entity[]
    for _ in 1:n
        push!(entities, new_entity!(world, (Position(0, 0),)))
    end

    observe!(world, evt, (Position,)) do entity
    end

    return world, entities, evt
end

function benchmark_event_match_1(args, n)
    world, entities, evt = args
    for entity in entities
        emit_event!(world, evt, entity, (Position,))
    end
    world
end

SUITE["benchmark_event_match_1 n=1000"] =
    @be setup_event_match_1(1000) benchmark_event_match_1(_, 1000) seconds = SECONDS

function setup_event_match_1_of_5(n::Int)
    reg = EventRegistry()
    evt = new_event_type!(reg, :Event)

    world = World(Position, Velocity)

    entities = Entity[]
    for _ in 1:n
        push!(entities, new_entity!(world, (Position(0, 0),)))
    end

    observe!(world, evt, (Position,)) do entity
    end

    for _ in 1:4
        observe!(world, evt, (Velocity,)) do entity
        end
    end

    return world, entities, evt
end

function benchmark_event_match_1_of_5(args, n)
    world, entities, evt = args
    for entity in entities
        emit_event!(world, evt, entity, (Position,))
    end
    world
end

SUITE["benchmark_event_match_1_of_5 n=1000"] =
    @be setup_event_match_1_of_5(1000) benchmark_event_match_1_of_5(_, 1000) seconds = SECONDS

function setup_event_capture(n::Int)
    reg = EventRegistry()
    evt = new_event_type!(reg, :Event)

    world = World(Position, Velocity)

    entities = Entity[]
    for _ in 1:n
        push!(entities, new_entity!(world, (Position(0, 0),)))
    end

    observe!(world, evt, (Position,)) do entity
        set_components!(world, entity, (Position(Float64(entity._id), 0),))
    end

    return world, entities, evt
end

function benchmark_event_capture(args, n)
    world, entities, evt = args
    for entity in entities
        emit_event!(world, evt, entity, (Position,))
    end
    world
end

SUITE["benchmark_event_capture n=1000"] =
    @be setup_event_capture(1000) benchmark_event_capture(_, 1000) seconds = SECONDS
