
function setup_world_set_1(n_entities::Int)
    world = World(Position, Velocity)

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    for e in entities
        set_components!(world, e, (Position(1, 2),))
    end

    return (entities, world)
end

function benchmark_world_set_1(args, n)
    entities, world = args
    for e in entities
        set_components!(world, e, (Position(1, 2),))
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_1 n=$(n)"] =
        @be setup_world_set_1($n) benchmark_world_set_1(_, $n) evals = 100 seconds = SECONDS
end
