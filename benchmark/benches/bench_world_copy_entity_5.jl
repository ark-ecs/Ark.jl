
function setup_world_copy_entity_5(n::Int)
    world = World(Position, Velocity, CompA, CompB, CompC)

    template = new_entity!(world, (Position(0, 0), Velocity(0, 0), CompA(0, 0), CompB(0, 0), CompC(0, 0)))

    # Run once to allocate memory
    entities = Vector{Entity}()
    for _ in 1:n
        e = copy_entity!(world, template)
        push!(entities, e)
    end

    for e in entities
        remove_entity!(world, e)
    end

    return world, template
end

function benchmark_world_copy_entity_5(args, n::Int)
    world, template = args
    for _ in 1:n
        copy_entity!(world, template)
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_copy_entity_5 n=$(n)"] =
        @be setup_world_copy_entity_5($n) benchmark_world_copy_entity_5(_, $n) evals = 1 seconds = SECONDS
end
