
using Random

function setup_world_shuffle(n_entities::Int)
    world = World(
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10},
    )

    for i in 1:n_entities
        new_entity!(
            world,
            (
                CompN{1}(i, i), CompN{2}(i, i), CompN{3}(i, i), CompN{4}(i, i), CompN{5}(i, i),
                CompN{6}(i, i), CompN{7}(i, i), CompN{8}(i, i), CompN{9}(i, i), CompN{10}(i, i),
            ),
        )
    end

    f = Filter(
        world,
        (
            CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
            CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10},
        ),
    )
    rng = Xoshiro(42)
    shuffle_entities!(rng, f)
    return (rng, f, n_entities)
end

function benchmark_world_shuffle(args)
    rng, f, _ = args
    shuffle_entities!(rng, f)
end

function benchmark_world_sort(args)
    _, f, _ = args
    sort_entities!(f; by=e -> f._world[e][CompN{1}].x)
end

function benchmark_world_partition(args)
    _, f, n = args
    partition_entities!(f; pred=e -> f._world[e][CompN{1}].x < n / 2)
end

for n in (100, 10_000)
    SUITE["benchmark_world_shuffle n=$(n)"] =
        @be setup_world_shuffle($n) benchmark_world_shuffle(_) seconds = SECONDS
end

for n in (100, 10_000)
    SUITE["benchmark_world_sort n=$(n)"] =
        @be setup_world_shuffle($n) benchmark_world_sort(_) evals = 1 seconds = SECONDS
end

for n in (100, 10_000)
    SUITE["benchmark_world_partition n=$(n)"] =
        @be setup_world_shuffle($n) benchmark_world_partition(_) evals = 1 seconds = SECONDS
end
