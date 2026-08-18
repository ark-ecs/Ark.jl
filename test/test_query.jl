
@testset "Query basic functionality" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    for i in 1:10
        query = Query(world, (Position, Velocity))
        @test Base.IteratorSize(typeof(query)) == Base.HasLength()
        @test query._filter.has_excluded == false
        @test count_tables(world, query) == 1
        @test count_entities(world, query) == 10
        count = 0
        for (entities, vec_pos, vec_vel) in query
            @test isa(vec_pos, FieldViewable{Position}) == true
            @test isa(vec_vel, FieldViewable{Velocity}) == true
            @test length(entities) == length(vec_pos)
            @test length(entities) == length(vec_vel)
            for i in eachindex(vec_pos)
                pos = vec_pos[i]
                vel = vec_vel[i]
                vec_pos[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
                count += 1
            end
            @test_throws(
                "InvalidStateException: cannot modify a locked world: " *
                "collect entities into a vector and apply changes after query iteration has completed",
                new_entity!(world, (Altitude(1), Health(2)))
            )
            @test is_locked(world) == true
            @test query._q_lock.closed == false
        end
        @test count == 10
        @test is_locked(world) == false
        @test query._q_lock.closed == true

        # Should not raise
        close!(query)
    end
end

@testset "Query preserves requested column order" begin
    world = TestWorld(Position, Velocity)

    new_entity!(world, (Position(1, 2), Velocity(3, 4)))

    _, velocities, positions = only(Query(world, (Velocity, Position)))

    @test eltype(velocities) == Velocity
    @test eltype(positions) == Position
    @test velocities[1] == Velocity(3, 4)
    @test positions[1] == Position(1, 2)

    query = Query(world, (Velocity, Position))
    @test string(query) == "Query((Velocity, Position))"
    close!(query)

    _, velocities, positions = only(Query(world, (Velocity,); optional=(Position,)))
    @test eltype(velocities) == Velocity
    @test eltype(positions) == Position
    @test velocities[1] == Velocity(3, 4)
    @test positions[1] == Position(1, 2)
end

@testset "Query Const components return read-only columns" begin
    world = TestWorld(Position, Velocity, Altitude)

    new_entity!(world, (Position(1, 2), Velocity(3, 4), Altitude(5)))

    _, positions, velocities = only(Query(world, (Const(Position), Velocity)))

    @test size(positions) == (1,)
    @test axes(positions) == (Base.OneTo(1),)
    @test positions isa ReadOnly
    @test !(velocities isa ReadOnly)
    @test eltype(positions) == Position
    @test positions[1] == Position(1, 2)
    @test velocities[1] == Velocity(3, 4)
    @test_throws Exception setindex!(positions, Position(10, 20), 1)
    @test_throws ArgumentError Const(MutableComponent)
    @test string(Const(Position)) == "Const(Position)"

    if !(typeof(positions) <: ReadOnly{<:Any,<:GPUVectorView})
        xs = positions.x
        @test xs isa ReadOnly
        @test eltype(xs) == Float64
        @test xs[1] == 1
        @test_throws Exception setindex!(xs, 10.0, 1)
    end

    velocities[1] = Velocity(5, 6)
    _, updated_positions, updated_velocities = only(Query(world, (Position, Velocity)))
    @test updated_positions[1] == Position(1, 2)
    @test updated_velocities[1] == Velocity(5, 6)

    _, _, altitudes = only(Query(world, (Position,); optional=(Const(Altitude),)))
    @test altitudes isa ReadOnly
    @test altitudes[1] == Altitude(5)
    @test_throws Exception setindex!(altitudes, Altitude(10), 1)

    filter = Filter(world, (Const(Position), Velocity); optional=(Const(Altitude),))
    @test string(filter) == "Filter((Const(Position), Velocity); optional=(Const(Altitude)))"
    _, filter_positions, filter_velocities, filter_altitudes = only(Query(world, filter))
    @test filter_positions isa ReadOnly
    @test !(filter_velocities isa ReadOnly)
    @test filter_altitudes isa ReadOnly

    registered_filter = Filter(world, (Const(Position),); register=true)
    _, registered_positions = only(Query(world, registered_filter))
    @test registered_positions isa ReadOnly
    unregister!(world, registered_filter)
end

@testset "Query from filter preserves requested column order" begin
    world = TestWorld(Position, Velocity)

    new_entity!(world, (Position(1, 2), Velocity(3, 4)))

    filter = Filter(world, (Velocity, Position))
    _, velocities, positions = only(Query(world, filter))

    @test eltype(velocities) == Velocity
    @test eltype(positions) == Position
    @test velocities[1] == Velocity(3, 4)
    @test positions[1] == Position(1, 2)

    query = Query(world, filter)
    @test string(query) == "Query((Velocity, Position))"
    close!(query)
end

@testset "Query from filter" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    filter = Filter(world, (Position, Velocity))
    query = Query(world, filter)
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10
    close!(query)
    count = 0
    for (entities, vec_pos, vec_vel) in Query(world, filter)
        count += length(entities)
    end
    @test count == 10
end

@testset "Query from registered filter" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    filter = Filter(world, (Position, Velocity); register=true)
    query = Query(world, filter)
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10
    close!(query)

    count = 0
    for (entities, vec_pos, vec_vel) in Query(world, filter)
        count += length(entities)
    end
    @test count == 10
end

@testset "Query with" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); with=(Altitude,))
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10

    count = 0
    for (ent, vec_pos, vec_vel) in query
        for i in eachindex(ent)
            e = ent[i]
            @test has_components(world, e, (Altitude,)) == true
            count += 1
        end
    end
    @test count == 10
end

@testset "Query without" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); without=(Altitude,))
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10

    count = 0
    for (ent, vec_pos, vec_vel) in query
        for i in eachindex(ent)
            e = ent[i]
            @test has_components(world, e, (Altitude,)) == false
            count += 1
        end
    end
    @test count == 10
end

@testset "Query optional" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); optional=(Altitude,))
    @test count_tables(world, query) == 2
    @test count_entities(world, query) == 20

    count = 0
    indices = Vector{Int}()
    arch = 1
    for (ent, vec_pos, vec_vel, vec_alt) in query
        if arch == 1
            @test vec_alt === nothing
        else
            @test vec_alt !== nothing
        end
        for i in eachindex(ent)
            e = ent[i]
            count += 1
        end
        arch += 1
    end
    @test count == 20
end

@testset "Query exclusive" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5), Health(6)))
    end

    @test_throws(
        "ArgumentError: cannot use 'exclusive' together with 'without'",
        Query(world, (Position, Velocity); without=(Altitude,), exclusive=true),
    )

    query = Query(world, (Position, Velocity); with=(Altitude,), exclusive=true)
    @test query._filter.has_excluded == true
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10

    count = 0
    for (ent, vec_pos, vec_vel) in query
        for i in eachindex(ent)
            e = ent[i]
            @test has_components(world, e, (Health,)) == false
            @test has_components(world, e, (Altitude,)) == true
            count += 1
        end
    end
    @test count == 10
end

@testset "Query relations" begin
    world = TestWorld(Dummy, Position, Velocity, Relation{ChildOf})
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), ChildOf() => parent1))
        new_entity!(world, (Position(i, i * 2), ChildOf() => parent2))
        new_entity!(world, (Position(i, i * 2), ChildOf() => parent3))
    end
    e = new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf() => parent4))
    remove_entity!(world, e)
    remove_entity!(world, parent4)

    query = Query(world, (Position,))
    @test count_tables(world, query) == 3
    @test count_entities(world, query) == 30
    cnt = 0
    for (entities, positions) in query
        cnt += length(entities)
    end
    @test cnt == 30

    query = Query(world, (Position, ChildOf => parent2))
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 10
    cnt = 0
    for (entities, positions, _) in query
        cnt += length(entities)
    end
    @test cnt == 10
end

@testset "Query multiple relations" begin
    world = TestWorld(Dummy, Position, Relation{ChildOf}, Relation{ChildOf2})
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0), ChildOf() => parent1, ChildOf2() => parent1))
    new_entities!(world, 11, (Position(0, 0), ChildOf() => parent1, ChildOf2() => parent2))
    new_entities!(world, 12, (Position(0, 0), ChildOf() => parent1, ChildOf2() => parent3))

    query = Query(world, (ChildOf => parent1,))
    @test count_tables(world, query) == 3
    @test count_entities(world, query) == 33
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 33

    query = Query(world, (ChildOf2 => parent2,))
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 11
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 11

    query = Query(world, (ChildOf => parent1, ChildOf2 => parent2))
    @test count_tables(world, query) == 1
    @test count_entities(world, query) == 11
    count = 0
    for (entities, _, _) in query
        count += length(entities)
    end
    @test count == 11

    query = Query(world, (ChildOf => parent4,))
    @test count_tables(world, query) == 0
    @test count_entities(world, query) == 0
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 0
end

@testset "Query empty" begin
    world = TestWorld(Dummy, Position, Velocity)

    query = Query(world, (Position, Velocity))
    @test_throws("ArgumentError: query must contain exactly one matching table", only(query))

    for i in 1:10
        new_entity!(world, (Position(i, i * 2),))
    end

    query = Query(world, (Position,))
    @test first(query) === only(query)

    query = Query(world, (Position, Velocity))
    @test count_tables(world, query) == 0
    @test count_entities(world, query) == 0

    count = 0
    arches = 0
    for (ent, vec_pos) in query
        for i in eachindex(ent)
            count += 1
        end
        arches += 1
    end
    @test count == 0
    @test arches == 0
end

@testset "Query no comps" begin
    world = TestWorld(Dummy, Position, Velocity)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2),))
        new_entity!(world, (Velocity(i, i * 2),))
    end

    query = Query(world, ())
    @test_throws("ArgumentError: query must contain exactly one matching table", only(query))

    query = Query(world, ())
    @test count_tables(world, query) == 2
    @test count_entities(world, query) == 20

    count = 0
    arches = 0
    for (ent,) in query
        for i in eachindex(ent)
            count += 1
        end
        arches += 1
    end
    @test count == 20
    @test arches == 2
end

@testset "Query StructArray" begin
    world = TestWorld(
        Dummy,
        Position,
        Velocity => Storage(StructArray),
    )

    for i in 1:10
        new_entity!(world, (Position(0, 0), Velocity(i, i)))
    end

    for (entities, vec) in Query(world, (Velocity,))
        @test isa(vec, StructArrayView)
        for i in eachindex(vec)
            pos = vec[i]
            vec[i] = Velocity(pos.dx + 1, pos.dy + 1)
        end
    end

    for arch in Query(world, (Position, Velocity))
        @unpack e, pos, (dx, dy) = arch
        @test isa(e, Entities)
        T = _storage_from_component(world, Velocity) <: StructArray ? SubArray : GPUVectorView
        @test isa(dx, T) && eltype(dx) == Float64
        @test isa(dy, T) && eltype(dy) == Float64
    end
end

@testset "Query FieldViewable" begin
    world = TestWorld(
        Dummy,
        Position,
        Velocity => Storage(StructArray),
        NoIsBits,
        Int64,
    )

    for i in 1:10
        new_entity!(world, (Position(i, i), Velocity(i, i), NoIsBits([]), Int64(1)))
    end

    for columns in Query(world, (Position, Velocity))
        @unpack _, (x, y), (dx, dy) = columns
        @test x isa FieldView
        @test y isa FieldView
        @test length(x) == 10
        @test x[1] == 1
        @test x[10] == 10
    end

    for (_, positions, no_isbits, int) in Query(world, (Position, NoIsBits, Int64))
        @test positions isa FieldViewable
        @test no_isbits isa FieldViewable
        @test int isa SubArray
    end

    for columns in Query(world, (Position, NoIsBits, Int64))
        @unpack _, (x, y), (vec,), int = columns
        @test x isa FieldView
        @test y isa FieldView
        @test vec isa FieldView
        @test int isa SubArray
    end
end

@testset "Query duplicates" begin
    world = TestWorld(
        Position,
        Velocity,
        Altitude,
        Health,
    )
    @test_throws(
        "ArgumentError: duplicate component types: Altitude, Health",
        Query(world, (Position, Velocity, Altitude); optional=(Altitude, Health), without=(Health,))
    )
end

@testset "Query eltype" begin
    world = TestWorld(
        Dummy,
        Position,
        Velocity => Storage(StructArray),
        Altitude,
        NoIsBits,
        Int64,
        Float64,
    )

    for i in 1:10
        new_entity!(world, (Position(i, i), Velocity(i, i), Altitude(0), NoIsBits([]), Int64(1), Float64(1.0)))
    end

    query = Query(world, (Position, Velocity, Int64); optional=(NoIsBits, Altitude, Float64))

    @inferred Tuple{
        Entities,
        FieldViews.FieldViewable{Position,1,_storage_from_component(world, Position)},
        StructArrayView{
            Velocity,
            @NamedTuple{
                dx::SubArray{Float64,1,Vector{Float64},Tuple{UnitRange{Int64}},true},
                dy::SubArray{Float64,1,Vector{Float64},Tuple{UnitRange{Int64}},true},
            },
        },
        SubArray{Int64,1,_storage_from_component(world, Int64),Tuple{Base.Slice{Base.OneTo{Int64}}},true},
        Union{Nothing,FieldViews.FieldViewable{NoIsBits,1,_storage_from_component(world, NoIsBits)}},
        Union{Nothing,FieldViews.FieldViewable{Altitude,1,_storage_from_component(world, Altitude)}},
        Union{
            Nothing,
            SubArray{Float64,1,_storage_from_component(world, Float64),Tuple{Base.Slice{Base.OneTo{Int64}}},true},
        },
    } Base.eltype(typeof(query))

    expected_type = Base.eltype(typeof(query))
    @inferred Union{Nothing,Tuple{expected_type,Any}} Base.iterate(query)
end

@testset "Query Const eltype" begin
    world = TestWorld(Position, Velocity, Altitude)

    new_entity!(world, (Position(1, 2), Velocity(3, 4), Altitude(5)))

    query = Query(world, (Const(Position), Velocity); optional=(Const(Altitude),))

    @inferred Tuple{
        Entities,
        ReadOnly{Position,FieldViews.FieldViewable{Position,1,_storage_from_component(world, Position)}},
        FieldViews.FieldViewable{Velocity,1,_storage_from_component(world, Velocity)},
        Union{Nothing,ReadOnly{Altitude,FieldViews.FieldViewable{Altitude,1,_storage_from_component(world, Altitude)}}},
    } Base.eltype(typeof(query))

    expected_type = Base.eltype(typeof(query))
    @inferred Union{Nothing,Tuple{expected_type,Any}} Base.iterate(query)
end

"""
@static if RUN_JET
@testset "Query JET" begin
    world = TestWorld(
        Position,
        Velocity => Storage(StructArray),
        Altitude,
        Health,
    )

    new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0)))

    f = () -> begin
        for (e, p, v) in Query(world, (Position, Vector); with=(Altitude,), without=(Health,))
            if length(e) != 1
                error("")
            end
        end
    end

    @test_opt f()
end
end
"""

@testset "Query error messages" begin
    world = TestWorld(Dummy, Position, Velocity)

    query = Query(world, (Position, Velocity))
    for _ in query
    end
    @test_throws(
        "InvalidStateException: query closed, queries can't be used multiple times",
        for _ in query
        end
    )

    query = Query(world, (Position, Velocity))
    close!(query)
    @test_throws(
        "InvalidStateException: query closed, queries can't be used multiple times",
        for _ in query
        end
    )
end

@testset "Single eval of rhs for unpack" begin
    world = TestWorld(Position => Storage(StructArray))
    new_entity!(world, (Position(1.0, 2.0),))

    calls = Ref(0)
    function onebatch(world)
        calls[] += 1
        q = Query(world, (Position,))
        cols = first(q)
        close!(q)
        return cols
    end

    @unpack entities, (x, y) = onebatch(world)

    @test calls[] == 1
    @test collect(entities)[1] isa Entity
    @test collect(x) == [1]
    @test collect(y) == [2]
end

@testset "Query show" begin
    world = TestWorld(
        Position,
        Velocity,
        Altitude,
        Health,
        CompN{1},
    )
    query = Query(world, (Position, Velocity))
    @test string(query) == "Query((Position, Velocity))"

    query = Query(world, (Position, Velocity); optional=(Altitude,), with=(Health,), exclusive=true)
    @test string(query) == "Query((Position, Velocity); optional=(Altitude), with=(Health), exclusive=true)"

    query = Query(world, (Position, Velocity); optional=(Altitude,), without=(Health,))
    @test string(query) == "Query((Position, Velocity); optional=(Altitude), without=(Health))"
end

@testset "Query cold compilation does not allocate in user functions" begin
    struct FreshA
        x::Float64
    end

    struct FreshB
        dx::Float64
    end

    world = TestWorld(FreshA, FreshB)
    for i in 1:500
        new_entity!(world, (FreshA(0.0), FreshB(0.0)))
    end

    function query_user_work!(world::World)
        s = 0.0
        for (ents, positions, velocities) in Query(world, (FreshA, FreshB))
            for i in eachindex(ents)
                pos = positions[i]
                vel = velocities[i]
                positions[i] = FreshA(pos.x + vel.dx)
                p, = get_components(world, ents[i], (FreshA,))
                s += p.x
            end
        end
        return s
    end

    query_user_work!(world)

    world2 = TestWorld(FreshA, FreshB)
    for i in 1:500
        new_entity!(world2, (FreshA(0.0), FreshB(0.0)))
    end

    allocs = @allocated query_user_work!(world2)
    if VERSION >= v"1.12"
        @test allocs == 0
    else
        @test allocs <= 48
    end
end

@testset "Query entity component access" begin
    world = TestWorld(Dummy, Position, Velocity, Altitude, Health)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    e2 = new_entity!(world, (Position(5, 6), Velocity(7, 8), Health(10)))
    e3 = new_entity!(world, (Health(1),))

    query = Query(world, (Position, Velocity))

    @test get_components(query, e1, (Position, Velocity)) == (Position(1, 2), Velocity(3, 4))
    @test get_components(query, e1, (Velocity, Position)) == (Velocity(3, 4), Position(1, 2))
    @test get_components(query, e1, (Position,)) == (Position(1, 2),)
    @test get_components(query, e2, (Position, Velocity)) == (Position(5, 6), Velocity(7, 8))
    @test get_components(query, e1, ()) == ()

    @test has_components(query, e1, (Position, Velocity)) == true
    @test has_components(query, e3, (Position,)) == false
    @test has_components(query, e3, (Position, Velocity)) == false
    @test has_components(query, e1, ()) == true

    @test set_components!(query, e1, (Position(0, 0),)) == (Position(0, 0),)
    @test get_components(query, e1, (Position,)) == (Position(0, 0),)
    set_components!(query, e1, (Velocity(1, 1), Position(2, 2)))
    @test get_components(world, e1, (Position, Velocity)) == (Position(2, 2), Velocity(1, 1))
    @test set_components!(query, e1, ()) == ()

    get_pos_vel(q, e) = get_components(q, e, (Position, Velocity))
    set_pos(q, e) = set_components!(q, e, (Position(2, 2),))
    has_pos_vel(q, e) = has_components(q, e, (Position, Velocity))
    @inferred get_pos_vel(query, e1)
    @inferred set_pos(query, e1)
    @inferred has_pos_vel(query, e1)

    @test query._q_lock.closed == false
    @test is_locked(world) == true
    @test count_tables(world, query) == 2
    @test count_entities(world, query) == 2

    count = 0
    for (entities, positions, velocities) in query
        count += length(entities)
    end
    @test count == 2
    @test query._q_lock.closed == true
    @test is_locked(world) == false
end

@testset "Query entity component access with Const" begin
    world = TestWorld(Position, Velocity, Altitude)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4), Altitude(5)))

    query = Query(world, (Const(Position), Velocity); optional=(Const(Altitude),))

    @test get_components(query, e1, (Position,)) == (Position(1, 2),)
    @test get_components(query, e1, (Const(Position), Altitude)) == (Position(1, 2), Altitude(5))
    @test set_components!(query, e1, (Velocity(0, 0),)) == (Velocity(0, 0),)

    @test_throws(
        "ArgumentError: component Position is read-only in the query",
        set_components!(query, e1, (Position(0, 0),))
    )
    @test_throws(
        "ArgumentError: component Altitude is read-only in the query",
        set_components!(query, e1, (Altitude(0),))
    )
    close!(query)
end

@testset "Query entity component access with optional" begin
    world = TestWorld(Position, Velocity, Health)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4), Health(10)))
    e2 = new_entity!(world, (Position(5, 6), Velocity(7, 8)))

    query = Query(world, (Position,); optional=(Health,))

    @test get_components(query, e1, (Position, Health)) == (Position(1, 2), Health(10))
    set_components!(query, e1, (Health(20),))
    @test get_components(query, e1, (Health,)) == (Health(20),)

    @test has_components(query, e1, (Health,)) == true
    @test has_components(query, e2, (Health,)) == false

    @test_throws("ArgumentError: entity has no Health component", get_components(query, e2, (Health,)))
    @test_throws("ArgumentError: entity has no Health component", set_components!(query, e2, (Health(1),)))
    close!(query)
end

@testset "Query entity component access errors" begin
    world = TestWorld(Dummy, Position, Velocity, Health)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    e2 = new_entity!(world, (Health(1),))
    dead = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    remove_entity!(world, dead)

    query = Query(world, (Position, Velocity))

    @test_throws(
        "ArgumentError: component Health is not part of the query on (Position, Velocity)",
        get_components(query, e1, (Health,))
    )
    @test_throws(
        "ArgumentError: component Health is not part of the query on (Position, Velocity)",
        set_components!(query, e1, (Health(1),))
    )
    @test_throws("ArgumentError: entity does not match query", get_components(query, e2, (Position,)))
    @test_throws("ArgumentError: entity does not match query", set_components!(query, e2, (Position(1, 1),)))
    @test_throws(
        "ArgumentError: component Health is not part of the query on (Position, Velocity)",
        has_components(query, e1, (Health,))
    )
    @test_throws("ArgumentError: can't get components of a dead entity", get_components(query, dead, (Position,)))
    @test_throws(
        "ArgumentError: can't check components of a dead entity",
        has_components(query, dead, (Position,))
    )
    @test_throws(
        "ArgumentError: can't set components of a dead entity",
        set_components!(query, dead, (Position(1, 1),))
    )
    @test_throws(
        "ArgumentError: duplicate component types: Position",
        get_components(query, e1, (Position, Position))
    )
    @test_throws(
        "ArgumentError: duplicate component types: Position",
        set_components!(query, e1, (Position(1, 1), Position(2, 2)))
    )

    @test get_components(query, e1, (Position, Velocity)) == (Position(1, 2), Velocity(3, 4))
    @test count_entities(world, query) == 1
    close!(query)
end

@testset "Query entity component access requires a matching entity" begin
    world = TestWorld(Position, Velocity, Altitude, Health, Relation{ChildOf})
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    matching = new_entity!(world, (Position(1, 2), Velocity(3, 4), ChildOf() => parent1))
    missing_with = new_entity!(world, (Position(5, 6), ChildOf() => parent1))
    excluded = new_entity!(world, (Position(7, 8), Velocity(9, 10), Altitude(11), ChildOf() => parent1))
    extra_component = new_entity!(world, (Position(12, 13), Velocity(14, 15), Health(16)))
    wrong_target = new_entity!(world, (Position(17, 18), Velocity(19, 20), ChildOf() => parent2))

    query = Query(world, (Position,); with=(Velocity,))
    @test get_components(query, matching, (Position,)) == (Position(1, 2),)
    @test_throws("ArgumentError: entity does not match query", get_components(query, missing_with, (Position,)))
    @test has_components(query, missing_with, (Position,)) == false
    close!(query)

    query = Query(world, (Position,); with=(Velocity,), without=(Altitude,))
    @test_throws("ArgumentError: entity does not match query", set_components!(query, excluded, (Position(0, 0),)))
    close!(query)

    query = Query(world, (Position, Velocity); exclusive=true)
    @test_throws("ArgumentError: entity does not match query", get_components(query, extra_component, (Position,)))
    close!(query)

    query = Query(world, (Position, ChildOf => parent1); with=(Velocity,))
    @test_throws("ArgumentError: entity does not match query", get_components(query, wrong_target, (Position,)))
    close!(query)
end

@testset "Query entity component access unchecked" begin
    world = TestWorld(Position, Velocity)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))

    query = Query(world, (Position, Velocity))
    @unchecked begin
        @test get_components(query, e1, (Position, Velocity)) == (Position(1, 2), Velocity(3, 4))
        set_components!(query, e1, (Position(5, 6),))
        @test get_components(query, e1, (Position,)) == (Position(5, 6),)
        @test has_components(query, e1, (Position, Velocity)) == true
    end
    close!(query)
end

@testset "Query entity component access does not allocate" begin
    world = TestWorld(Position, Velocity)

    entities = [new_entity!(world, (Position(i, i), Velocity(1, 1))) for i in 1:100]

    function query_entity_access!(query, entities)
        s = 0.0
        for e in entities
            pos, vel = get_components(query, e, (Position, Velocity))
            set_components!(query, e, (Position(pos.x + vel.dx, pos.y + vel.dy),))
            s += pos.x
        end
        return s
    end

    query = Query(world, (Position, Velocity))
    query_entity_access!(query, entities)
    if VERSION >= v"1.11"
        @test @allocated(query_entity_access!(query, entities)) == 0
    else
        @test @allocated(query_entity_access!(query, entities)) == 16
    end

    close!(query)
end
