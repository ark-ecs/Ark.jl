
using Random

function setup_world_shuffle(n_entities::Int)
    world = World(
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10}
    )

    for _ in 1:n_entities
        new_entity!(world, (
            CompN{1}(0, 0), CompN{2}(0, 0), CompN{3}(0, 0), CompN{4}(0, 0), CompN{5}(0, 0),
            CompN{6}(0, 0), CompN{7}(0, 0), CompN{8}(0, 0), CompN{9}(0, 0), CompN{10}(0, 0),
        ))
    end

    f = Filter(world, (
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10}
    ))
    rng = Xoshiro(42)
    return (rng, f)
end

function benchmark_world_shuffle(args)
    rng, f = args
    shuffle_entities!(rng, f)
end

for n in (100, 10_000)
    SUITE["benchmark_world_shuffle n=$(n)"] =
        @be setup_world_shuffle($n) benchmark_world_shuffle(_) seconds = SECONDS
end
