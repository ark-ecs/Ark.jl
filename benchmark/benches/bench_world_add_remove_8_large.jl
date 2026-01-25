
function setup_world_add_remove_8_large(n_entities::Int)
    world = World(Position,
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10},
        CompN{11}, CompN{12}, CompN{13}, CompN{14}, CompN{15},
        CompN{16}, CompN{17}, CompN{18}, CompN{19}, CompN{20},
        CompN{21}, CompN{22}, CompN{23}, CompN{24}, CompN{25},
        CompN{26}, CompN{27}, CompN{28}, CompN{29}, CompN{30},
        CompN{31}, CompN{32}, CompN{33}, CompN{34}, CompN{35},
        CompN{36}, CompN{37}, CompN{38}, CompN{39}, CompN{40},
        CompN{41}, CompN{42}, CompN{43}, CompN{44}, CompN{45},
        CompN{46}, CompN{47}, CompN{48}, CompN{49}, CompN{50},
        CompN{51}, CompN{52}, CompN{53}, CompN{54}, CompN{55},
        CompN{56}, CompN{57}, CompN{58}, CompN{59}, CompN{60},
        CompN{61}, CompN{62}, CompN{63}, CompN{64}, CompN{65},
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

function benchmark_world_add_remove_8_large(args, n)
    entities, world = args
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
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_8_large n=$(n)"] =
        @be setup_world_add_remove_8_large($n) benchmark_world_add_remove_8_large(_, $n) seconds = SECONDS
end
