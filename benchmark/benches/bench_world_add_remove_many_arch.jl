using Random

# Entities start from a distinct component subset (bit pattern of their index over
# CompN{1}..CompN{10}), so every archetype transition cycles through a different
# graph node. CompN{11}..CompN{14} are reserved for the churn below.
function setup_world_add_remove_many_arch(n_entities::Int)
    world = World(
        Position,
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10},
        CompN{11}, CompN{12}, CompN{13}, CompN{14};
        boxed=BOXED,
    )

    all_comps = (
        CompN{1}(0, 0),
        CompN{2}(0, 0),
        CompN{3}(0, 0),
        CompN{4}(0, 0),
        CompN{5}(0, 0),
        CompN{6}(0, 0),
        CompN{7}(0, 0),
        CompN{8}(0, 0),
        CompN{9}(0, 0),
        CompN{10}(0, 0),
    )

    comps = Any[]
    entities = Vector{Entity}()
    for i in 1:n_entities
        push!(comps, Position(i, i * 2))
        for (j, comp) in enumerate(all_comps)
            m = 1 << (j - 1)
            if i & m == m
                push!(comps, comp)
            end
        end
        push!(entities, new_entity!(world, (comps...,)))
        resize!(comps, 0)
    end

    # Pre-create the target archetypes (and their tables/columns) so that the
    # benchmark loop itself does not allocate.
    for e in entities
        add_components!(world[e],
            (CompN{11}(0, 0), CompN{12}(0, 0), CompN{13}(0, 0), CompN{14}(0, 0)),
        )
    end
    for e in entities
        remove_components!(world[e],
            (CompN{11}, CompN{12}, CompN{13}, CompN{14}),
        )
    end

    rng = Xoshiro(42)
    shuffle!(rng, entities)

    return (entities, world)
end

function benchmark_world_add_remove_many_arch(args, n)
    entities, world = args
    for e in entities
        add_components!(world[e],
            (CompN{11}(0, 0), CompN{12}(0, 0), CompN{13}(0, 0), CompN{14}(0, 0)),
        )
    end
    for e in entities
        remove_components!(world[e],
            (CompN{11}, CompN{12}, CompN{13}, CompN{14}),
        )
    end
end

for n in (100, 1_000)
    SUITE["benchmark_world_add_remove_many_arch n=$(n)"] =
        @be setup_world_add_remove_many_arch($n) benchmark_world_add_remove_many_arch(_, $n) seconds = SECONDS
end
