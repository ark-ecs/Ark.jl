
function setup_world_new_entity_5_rel(n::Int)
    world = World(Position, Velocity, CompA, CompB, Relation{ChildOf})
    parent = new_entity!(world, ())

    # Run once to allocate memory
    entities = Vector{Entity}()
    for _ in 1:n
        e = new_entity!(world, (Position(0, 0), Velocity(0, 0), CompA(0, 0), CompB(0, 0), ChildOf() => parent))
        push!(entities, e)
    end

    for e in entities
        remove_entity!(world, e)
    end

    return world, parent
end

function benchmark_world_new_entity_5_rel(args, n::Int)
    world, parent = args
    for _ in 1:n
        new_entity!(world, (Position(0, 0), Velocity(0, 0), CompA(0, 0), CompB(0, 0), ChildOf() => parent))
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_new_entity_5_rel n=$(n)"] =
        @be setup_world_new_entity_5_rel($n) benchmark_world_new_entity_5_rel(_, $n) evals = 1 seconds = SECONDS
end
