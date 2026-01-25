
function setup_world_update_5(n_entities::Int)
    world = World(Position, Velocity, CompA, CompB, CompC)

    entities = Vector{Entity}()
    for i in 1:n_entities
        e = new_entity!(world, (Position(i, i * 2), Velocity(0, 0), CompA(0, 0), CompB(0, 0), CompC(0, 0)))
        push!(entities, e)
    end

    for e in entities
        pos, vel, a, b, c = get_components(world, e, (Position, Velocity, CompA, CompB, CompC))
        set_components!(world, e,
            (Position(pos.x + 1, 0), Velocity(vel.dx + 1, 0), CompA(a.x + 1, 0), CompB(b.x + 1, 0), CompC(c.x + 1, 0)),
        )
    end

    return (entities, world)
end

function benchmark_world_update_5(args, n)
    entities, world = args
    sum = 0.0
    for e in entities
        pos, vel, a, b, c = get_components(world, e, (Position, Velocity, CompA, CompB, CompC))
        set_components!(world, e,
            (Position(pos.x + 1, 0), Velocity(vel.dx + 1, 0), CompA(a.x + 1, 0), CompB(b.x + 1, 0), CompC(c.x + 1, 0)),
        )
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_update_5 n=$(n)"] =
        @be setup_world_update_5($n) benchmark_world_update_5(_, $n) evals = 100 seconds = SECONDS
end
