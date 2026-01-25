
function setup_world_add_remove_8_soa(n_entities::Int)
    world = World(
        Position => Storage{StructArray},
        CompN{1} => Storage{StructArray},
        CompN{2} => Storage{StructArray},
        CompN{3} => Storage{StructArray},
        CompN{4} => Storage{StructArray},
        CompN{5} => Storage{StructArray},
        CompN{6} => Storage{StructArray},
        CompN{7} => Storage{StructArray},
        CompN{8} => Storage{StructArray},
    )

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2),))
        push!(entities, e)
    end

    for e in entities
        add_components!(world, e,
            (CompN{1}(0, 0), CompN{2}(0, 0), CompN{3}(0, 0), CompN{4}(0, 0),
                CompN{5}(0, 0), CompN{6}(0, 0), CompN{7}(0, 0), CompN{8}(0, 0)),
        )
    end
    for e in entities
        remove_components!(world, e,
            (CompN{1}, CompN{2}, CompN{3}, CompN{4},
                CompN{5}, CompN{6}, CompN{7}, CompN{8}),
        )
    end

    return (entities, world)
end

function benchmark_world_add_remove_8_soa(args, n)
    entities, world = args
    for e in entities
        add_components!(
            world,
            e,
            (CompN{1}(0, 0), CompN{2}(0, 0), CompN{3}(0, 0), CompN{4}(0, 0),
                CompN{5}(0, 0), CompN{6}(0, 0), CompN{7}(0, 0), CompN{8}(0, 0))
        )
    end
    for e in entities
        remove_components!(
            world,
            e,
            (CompN{1}, CompN{2}, CompN{3}, CompN{4},
                CompN{5}, CompN{6}, CompN{7}, CompN{8})
        )
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_8_soa n=$(n)"] =
        @be setup_world_add_remove_8_soa($n) benchmark_world_add_remove_8_soa(_, $n) seconds = SECONDS
end
