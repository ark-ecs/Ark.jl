
@testset "Query basic functionality" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    for i in 1:10
        query = Query(world, (Position, Velocity))
        @test Base.IteratorSize(typeof(query)) == Base.SizeUnknown()
        @test query._filter.has_excluded == false
        @test length(query) == 1
        @test count_entities(query) == 10
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
        end
        @test count == 10
        @test is_locked(world) == false
    end
end

@testset "Query from filter" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    filter = Filter(world, (Position, Velocity))
    query = Query(filter)
    @test length(query) == 1
    @test count_entities(query) == 10
    close!(query)
    count = 0
    for (entities, vec_pos, vec_vel) in Query(filter)
        count += length(entities)
    end
    @test count == 10
end

@testset "Query from registered filter" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    for i in 1:10
        new_entity!(world, (Altitude(1), Health(2)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Health(3)))
    end

    filter = Filter(world, (Position, Velocity); register=true)
    query = Query(filter)
    @test length(query) == 1
    @test count_entities(query) == 10
    close!(query)

    count = 0
    for (entities, vec_pos, vec_vel) in Query(filter)
        count += length(entities)
    end
    @test count == 10
end

@testset "Query with" begin
    world = World(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); with=(Altitude,))
    @test length(query) == 1
    @test count_entities(query) == 10

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
    world = World(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); without=(Altitude,))
    @test length(query) == 1
    @test count_entities(query) == 10

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
    world = World(Dummy, Position, Velocity, Altitude)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
        new_entity!(world, (Position(i, i * 2), Velocity(1, 1), Altitude(5)))
    end

    query = Query(world, (Position, Velocity); optional=(Altitude,))
    @test length(query) == 2
    @test count_entities(query) == 20

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
    world = World(Dummy, Position, Velocity, Altitude, Health)

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
    @test length(query) == 1
    @test count_entities(query) == 10

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
    world = World(Dummy, Position, Velocity, ChildOf)
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())

    for i in 1:10
        new_entity!(world, (Position(i, i * 2), ChildOf()); relations=(ChildOf => parent1,))
        new_entity!(world, (Position(i, i * 2), ChildOf()); relations=(ChildOf => parent2,))
        new_entity!(world, (Position(i, i * 2), ChildOf()); relations=(ChildOf => parent3,))
    end
    e = new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent4,))
    remove_entity!(world, e)
    remove_entity!(world, parent4)

    query = Query(world, (Position,))
    @test length(query) == 3
    @test count_entities(query) == 30
    cnt = 0
    for (entities, positions) in query
        cnt += length(entities)
    end
    @test cnt == 30

    query = Query(world, (Position, ChildOf); relations=(ChildOf => parent2,))
    @test length(query) == 1
    @test count_entities(query) == 10
    cnt = 0
    for (entities, positions, _) in query
        cnt += length(entities)
    end
    @test cnt == 10
end

@testset "Query multiple relations" begin
    world = World(Dummy, Position, ChildOf, ChildOf2)
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent1, ChildOf2 => parent1),
    )
    new_entities!(world, 11, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent1, ChildOf2 => parent2),
    )
    new_entities!(world, 12, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent1, ChildOf2 => parent3),
    )

    query = Query(world, (ChildOf,); relations=(ChildOf => parent1,))
    @test length(query) == 3
    @test count_entities(query) == 33
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 33

    query = Query(world, (ChildOf2,); relations=(ChildOf2 => parent2,))
    @test length(query) == 1
    @test count_entities(query) == 11
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 11

    query = Query(world, (ChildOf, ChildOf2); relations=(ChildOf => parent1, ChildOf2 => parent2))
    @test length(query) == 1
    @test count_entities(query) == 11
    count = 0
    for (entities, _, _) in query
        count += length(entities)
    end
    @test count == 11

    query = Query(world, (ChildOf,); relations=(ChildOf => parent4,))
    @test length(query) == 0
    @test count_entities(query) == 0
    count = 0
    for (entities, _) in query
        count += length(entities)
    end
    @test count == 0
end

@testset "Query empty" begin
    world = World(Dummy, Position, Velocity)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2),))
    end

    query = Query(world, (Position, Velocity))
    @test length(query) == 0
    @test count_entities(query) == 0

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
    world = World(Dummy, Position, Velocity)

    for i in 1:10
        new_entity!(world, (Position(i, i * 2),))
        new_entity!(world, (Velocity(i, i * 2),))
    end

    query = Query(world, ())
    @test length(query) == 2
    @test count_entities(query) == 20

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
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
    )

    for i in 1:10
        new_entity!(world, (Position(0, 0), Velocity(i, i)))
    end

    for (entities, vec) in Query(world, (Velocity,))
        @test isa(vec, _StructArrayView)
        for i in eachindex(vec)
            pos = vec[i]
            vec[i] = Velocity(pos.dx + 1, pos.dy + 1)
        end
    end

    for arch in Query(world, (Position, Velocity))
        @unpack e, pos, (dx, dy) = arch
        @test isa(e, Entities)
        T = _storage_from_component(world, Velocity) == StructArray ? SubArray : TestVector
        @test isa(dx, T{Float64})
        @test isa(dy, T{Float64})
    end
end

@testset "Query FieldViewable" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
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
    world = World(
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
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
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
        _StructArrayView{
            Velocity,
            @NamedTuple{
                dx::SubArray{Float64,1,Vector{Float64},Tuple{UnitRange{Int64}},true},
                dy::SubArray{Float64,1,Vector{Float64},Tuple{UnitRange{Int64}},true},
            },
            UnitRange{Int64},
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

"""
@static if RUN_JET
@testset "Query JET" begin
    world = World(
        Position,
        Velocity => Storage{StructArray},
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
    world = World(Dummy, Position, Velocity)

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

@testset "Query show" begin
    world = World(
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
