
using Random

sort_key(world) = e -> world[e][CompN{1}].x

function setup_world_shuffle(n_entities::Int)
    world = World(
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10};
        boxed=BOXED,
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
    pred = let world = world, limit = n_entities / 2
        e -> world[e][CompN{1}].x < limit
    end

    rng = Xoshiro(42)

    shuffle_entities!(rng, world, f)
    sort_entities!(world, f; by=sort_key(world))
    partition_entities!(world, f; pred)

    shuffle_entities!(rng, world, f)

    return (rng, world, f, pred)
end

function benchmark_world_shuffle(args)
    rng, world, f, _ = args
    shuffle_entities!(rng, world, f)
end

function benchmark_world_sort(args)
    _, world, f, _ = args
    sort_entities!(world, f; by=sort_key(world))
end

function benchmark_world_partition(args)
    _, world, f, pred = args
    partition_entities!(world, f; pred)
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
