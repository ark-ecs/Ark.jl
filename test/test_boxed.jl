
@testset "Boxed storage flag" begin
    world = World(Position, Velocity; boxed=true)
    @test Ark._is_boxed(typeof(_storage(world)))
    @test _storage(world)._storages isa Vector{Any}
    @test !Ark._is_boxed(typeof(_storage(World(Position, Velocity))))
    @test _storage(World(Position, Velocity))._storages isa Tuple

    # The two modes are independent, and compose.
    @test !Ark._is_erased(typeof(_storage(World(Position, Velocity; boxed=true))))
    both = _storage(World(Position, Velocity; boxed=true, erased=true))
    @test Ark._is_boxed(typeof(both)) && Ark._is_erased(typeof(both))
end

@testset "Boxed storage matches tuple storage" begin
    function run_ops!(world)
        log = Any[]
        e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
        e2 = new_entity!(world, (Position(5, 6),))
        new_entities!(world, 10, (Position(0, 0), Velocity(1, 1)))

        add_components!(world, e2, (Velocity(7, 8),))
        push!(log, get_components(world, e2, (Position, Velocity)))

        set_components!(world, e2, (Position(9, 10),))
        push!(log, get_components(world, e2, (Position,)))

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

        shuffle_entities!(world, Filter(world, (Position,)))
        push!(log, count_entities(world, Filter(world, (Position,))))

        remove_entity!(world, e1)
        push!(log, (is_alive(world, e1), count_entities(world, Filter(world, (Position,)))))

        remove_entities!(world, Filter(world, (Position, Velocity)))
        push!(log, count_entities(world, Filter(world, (Position,))))

        reset!(world)
        push!(log, count_entities(world, Filter(world, (Position,))))
        return log
    end

    reference = run_ops!(World(Position, Velocity, Health))
    @test run_ops!(World(Position, Velocity, Health; boxed=true)) == reference
    @test run_ops!(World(Position, Velocity, Health; boxed=true, erased=true)) == reference
end

@testset "Boxed storage with relations" begin
    world = World(Position, Relation{ChildOf}; boxed=true)
    parent = new_entity!(world, (Position(0, 0),))
    child = new_entity!(world, (Position(1, 1), ChildOf() => parent))

    @test get_relations(world, child, (ChildOf,)) == (parent,)

    remove_entity!(world, parent)
    @test !is_alive(world, child) || get_relations(world, child, (ChildOf,)) == (zero_entity,)
end

@testset "Boxed storage with mixed storage modes" begin
    world = World(
        Position => Storage{StructArray},
        Velocity => Storage{Vector},
        Health => Storage{Vector};
        boxed=true,
    )
    entity = new_entity!(world, (Position(1, 2), Velocity(3, 4), Health(5)))
    @test get_components(world, entity, (Position, Velocity, Health)) ==
          (Position(1, 2), Velocity(3, 4), Health(5))

    for (entities, positions) in Query(world, (Position,))
        @test length(entities) == 1
        @test positions[1] == Position(1, 2)
    end
end

# A boxed world reads its storages back out of a `Vector{Any}` with a type assertion. If one
# of those assertions were ever dropped the code would still be correct, but it would fall
# back to dynamic dispatch and start allocating - which is what these tests guard.
# The component types have to be literals inside the callee: the public API takes them as a
# tuple of types, so `@inferred` on a direct call would only see `Tuple{DataType}` and report
# `Any` for every world, boxed or not.
_boxed_get_position(world, entity) = get_components(world, entity, (Position,))
_boxed_has_velocity(world, entity) = has_components(world, entity, (Velocity,))
_boxed_add_velocity!(world, entity) = add_components!(world, entity, (Velocity(1, 2),))

@testset "Boxed storage is type stable" begin
    function check_inference(world)
        stores = _storage(world)
        @test @inferred(Ark._get_storage(stores, Position)) isa
              Ark._ComponentStorage{Position,Vector{Position}}
        @test @inferred(Ark._get_storage(stores, Health)) isa
              Ark._ComponentStorage{Health,Vector{Health}}

        entity = new_entity!(world, (Position(1, 2),))
        @test @inferred(_boxed_get_position(world, entity)) == (Position(1, 2),)
        @test @inferred(_boxed_has_velocity(world, entity)) == false
        @inferred _boxed_add_velocity!(world, entity)
        @test @inferred(_boxed_has_velocity(world, entity)) == true
        return nothing
    end

    check_inference(World(Position, Velocity, Health; boxed=true))
    check_inference(World(Position, Velocity, Health; boxed=true, erased=true))
    check_inference(World(Position, Velocity, Health))
end

@testset "Boxed storage does not allocate" begin
    function structural!(world, entity)
        add_components!(world, entity, (Velocity(1, 2),))
        remove_components!(world, entity, (Velocity,))
        exchange_components!(world, entity; add=(Health(1),), remove=())
        exchange_components!(world, entity; add=(), remove=(Health,))
        return nothing
    end
    function accessors!(world, entity)
        (p,) = get_components(world, entity, (Position,))
        set_components!(world, entity, (Position(p.x + 1, p.y),))
        return nothing
    end
    function churn!(world)
        for _ in 1:10
            entity = new_entity!(world, (Position(1, 1),))
            add_components!(world, entity, (Velocity(1, 1),))
            remove_entity!(world, entity)
        end
        return nothing
    end
    function iterate!(world)
        total = 0.0
        for (entities, positions) in Query(world, (Position,))
            for i in eachindex(entities)
                @inbounds total += positions[i].x
            end
        end
        return total
    end

    for kwargs in ((;), (; boxed=true), (; erased=true), (; boxed=true, erased=true))
        world = World(Position, Velocity, Health; kwargs...)
        for _ in 1:50
            new_entity!(world, (Position(1, 1),))
        end
        entity = new_entity!(world, (Position(0, 0),))

        structural!(world, entity)
        accessors!(world, entity)
        churn!(world)
        iterate!(world)

        @test @allocated(structural!(world, entity)) == 0
        @test @allocated(accessors!(world, entity)) == 0
        @test @allocated(churn!(world)) == 0
        @test @allocated(iterate!(world)) == 0
    end
end
