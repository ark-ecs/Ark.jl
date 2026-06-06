struct DiskRelation
    weight::Int
end

function _disk_snapshot(world)
    values = Dict{Entity,Position}()
    for (entities, positions) in Query(world, (Position,))
        for i in eachindex(entities)
            values[entities[i]] = positions[i]
        end
    end
    return values
end

@testset "DiskVector interface" begin
    dv = DiskVector{Int}()

    @test length(dv) == 0
    @test isempty(getfield(dv, :path))

    sizehint!(dv, 4)
    @test length(dv) == 0
    @test isfile(getfield(dv, :path))

    push!(dv, 1)
    push!(dv, 2)
    resize!(dv, 4)
    dv[3] = 3
    dv[4] = 4
    @test collect(dv) == [1, 2, 3, 4]

    fill!(view(dv, 2:3), 9)
    @test collect(dv) == [1, 9, 9, 4]

    @test pop!(dv) == 4
    @test collect(dv) == [1, 9, 9]

    dv2 = DiskVector{Int}()
    resize!(dv2, length(dv))
    copyto!(dv2, 1, dv, 1, length(dv))
    @test collect(dv2) == collect(dv)

    dv3 = DiskVector{Int}()
    resize!(dv3, length(dv))
    unsafe_copyto!(dv3, 1, dv, 1, length(dv))
    @test collect(dv3) == collect(dv)

    dv4 = similar(dv, Int, (2,))
    @test dv4 isa DiskVector{Int}
    @test length(dv4) == 2

    empty!(dv)
    @test isempty(dv)

    @test_throws(
        "ArgumentError: DiskVector storage requires an isbits component type, got NoIsBits",
        DiskVector{NoIsBits}()
    )
    @test_throws(
        "ArgumentError: DiskVector storage requires a nonzero-size component type, got LabelComponent",
        DiskVector{LabelComponent}()
    )
end

@testset "DiskVector validation" begin
    @test_throws(
        "ArgumentError: DiskVector storage requires an isbits component type, got NoIsBits",
        World(NoIsBits => Storage{DiskVector})
    )
    @test_throws(
        "ArgumentError: DiskVector storage requires an isbits component type, got MutableComponent",
        World(MutableComponent => Storage{DiskVector}; allow_mutable=true)
    )
    @test_throws(
        "ArgumentError: DiskVector storage requires a nonzero-size component type, got LabelComponent",
        World(LabelComponent => Storage{DiskVector})
    )

    world = World(Int64 => Storage{DiskVector})
    entity = new_entity!(world, (1,))
    @test get_components(world, entity, (Int64,)) == (1,)
end

@testset "DiskVector components" begin
    world = World(
        A => Storage{DiskVector},
        B => Storage{DiskVector},
        Relation{DiskRelation} => Storage{DiskVector},
    )

    e1 = new_entity!(world, (A(2.0), B(2.0)))
    @test get_components(world, e1, (A, B)) == (A(2.0), B(2.0))

    e2 = new_entity!(world, (A(2.0), B(2.0), DiskRelation(1) => e1))
    @test get_components(world, e2, (A, B, DiskRelation)) == (A(2.0), B(2.0), DiskRelation(1))
    @test get_relations(world, e2, (DiskRelation,)) == (e1,)

    a, b, rel = get_components(world, e2, (A, B, DiskRelation))
    set_components!(world, e2, (A(a.x + 1.0), B(b.x + 1.0), rel))
    @test get_components(world, e2, (A, B)) == (A(3.0), B(3.0))

    remove_components!(world, e2, (A, DiskRelation))
    @test has_components(world, e2, (A, DiskRelation)) == false
    @test get_components(world, e2, (B,)) == (B(3.0),)

    add_components!(world, e2, (A(4.0), DiskRelation(2) => e1))
    @test has_components(world, e2, (A, DiskRelation)) == true
    @test get_components(world, e2, (A, DiskRelation)) == (A(4.0), DiskRelation(2))
    @test get_relations(world, e2, (DiskRelation,)) == (e1,)

    e3 = copy_entity!(world, e2)
    @test get_components(world, e3, (A, B, DiskRelation)) == (A(4.0), B(3.0), DiskRelation(2))

    remove_entity!(world, e2)
    @test is_alive(world, e2) == false
    @test is_alive(world, e1) == true

    reset!(world)
    @test isempty(collect(Query(world, (A,))))
end

@testset "DiskVector query and batch operations" begin
    world = World(
        Position => Storage{DiskVector},
        Velocity => Storage{DiskVector},
        Health => Storage{DiskVector},
        Int64 => Storage{DiskVector},
    )

    new_entities!(world, 10, (Position, Velocity, Health, Int64)) do (entities, positions, velocities, healths, ints)
        @test positions isa FieldViewable
        @test velocities isa FieldViewable
        @test healths isa FieldViewable
        @test ints isa SubArray
        for i in eachindex(entities)
            positions[i] = Position(i, i)
            velocities[i] = Velocity(2i, 3i)
            healths[i] = Health(i)
            ints[i] = i
        end
    end

    for columns in Query(world, (Position, Velocity, Int64))
        @unpack _, (x, y), (dx, dy), ints = columns
        @test x isa FieldView
        @test y isa FieldView
        @test dx isa FieldView
        @test dy isa FieldView
        @test ints isa SubArray
        for i in eachindex(x)
            x[i] += dx[i]
            y[i] += dy[i]
            ints[i] += 1
        end
    end

    for (_, positions, ints) in Query(world, (Position, Int64))
        for i in eachindex(positions)
            @test positions[i] == Position(3i, 4i)
            @test ints[i] == i + 1
        end
    end

    before = _disk_snapshot(world)
    filter = Filter(world, (Position, Health))
    shuffle_entities!(filter)
    @test _disk_snapshot(world) == before

    sort_entities!(filter)
    @test _disk_snapshot(world) == before

    partition_entities!(filter; pred=e -> isodd(e._id))
    @test _disk_snapshot(world) == before
end
