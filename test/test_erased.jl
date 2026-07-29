
@testset "Erased dispatch flag" begin
    world = World(Position, Velocity; mode=:boxed)
    @test Ark._is_erased(typeof(_storage(world)))
    @test !Ark._is_erased(typeof(_storage(World(Position, Velocity))))
end

@testset "Erased dispatch matches default dispatch" begin
    function run_ops!(world)
        log = Any[]
        e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
        e2 = new_entity!(world, (Position(5, 6),))
        new_entities!(world, 10, (Position(0, 0), Velocity(1, 1)))

        add_components!(world, e2, (Velocity(7, 8),))
        push!(log, get_components(world, e2, (Position, Velocity)))

        exchange_components!(world, e1; add=(Health(42),), remove=(Velocity,))
        push!(log, (get_components(world, e1, (Position, Health)), has_components(world, e1, (Velocity,))))

        copied = copy_entity!(world, e1)
        push!(log, get_components(world, copied, (Position, Health)))

        remove_components!(world, e2, (Velocity,))
        push!(log, has_components(world, e2, (Velocity,)))

        add_components!(world, Filter(world, (Position, Velocity)), (Health(7),))
        push!(log, count_entities(world, Filter(world, (Health,))))
        remove_components!(world, Filter(world, (Health,)), (Health,))
        push!(log, count_entities(world, Filter(world, (Health,))))

        sort_entities!(world, Filter(world, (Position,)); by=e -> -e._id)
        for (entities, positions) in Query(world, (Position,))
            push!(log, (length(entities), sum(p.x for p in positions)))
        end

        remove_entity!(world, e1)
        push!(log, (is_alive(world, e1), count_entities(world, Filter(world, (Position,)))))

        remove_entities!(world, Filter(world, (Position, Velocity)))
        push!(log, count_entities(world, Filter(world, (Position,))))

        reset!(world)
        push!(log, count_entities(world, Filter(world, (Position,))))
        return log
    end

    @test run_ops!(World(Position, Velocity, Health; mode=:boxed)) ==
          run_ops!(World(Position, Velocity, Health))
end

@testset "Erased dispatch with relations" begin
    world = World(Position, Relation{ChildOf}; mode=:boxed)
    parent = new_entity!(world, (Position(0, 0),))
    child = new_entity!(world, (Position(1, 1), ChildOf() => parent))

    @test get_relations(world, child, (ChildOf,)) == (parent,)

    remove_entity!(world, parent)
    @test !is_alive(world, child) || get_relations(world, child, (ChildOf,)) == (zero_entity,)
end
