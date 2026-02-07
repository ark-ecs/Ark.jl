
function setup_world_shuffle(n_entities::Int)
    world = World(Position, Velocity)
    for i in 1:n_entities
        new_entity!(world, (Position(i, i), Velocity(i, i)))
    end
    f = Filter(world, (Position, Velocity))
    return (f, world)
end

function benchmark_world_shuffle(args)
    f, world = args
    shuffle!(f)
end

for n in (100, 10_000)
    SUITE["benchmark_world_shuffle n=$(n)"] =
        @be setup_world_shuffle($n) benchmark_world_shuffle(_) seconds = SECONDS
end
