
function setup_world_new_entity_1(n::Int)
    world = World(Position, Velocity)

    # Run once to allocate memory
    entities = Vector{Entity}()
    for _ in 1:n
        e = new_entity!(world, (Position(0, 0),))
        push!(entities, e)
    end

    for e in entities
        remove_entity!(world, e)
    end

    return world
end

function benchmark_world_new_entity_1(args, n::Int)
    world = args
    for _ in 1:n
        e = new_entity!(world, (Position(0, 0),))
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_new_entity_1 n=$(n)"] =
        @be setup_world_new_entity_1($n) benchmark_world_new_entity_1(_, $n) evals = 1 seconds = SECONDS
end
