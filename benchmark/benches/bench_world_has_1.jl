
function setup_world_has_1(n_entities::Int)
    world = World(Position, Velocity)

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    return (entities, world)
end

function benchmark_world_has_1(args, n)
    entities, world = args
    sum = 0
    for e in entities
        sum += (has_components(world, e, (Position,))) % Int
    end
    return sum
end

for n in (100, 10_000)
    SUITE["benchmark_world_has_1 n=$(n)"] =
        @be setup_world_has_1($n) benchmark_world_has_1(_, $n) evals = 100 seconds = SECONDS
end
