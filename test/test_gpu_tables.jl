
using KernelAbstractions

struct TabPos
    x::Float64
    y::Float64
end

struct TabVel
    dx::Float64
    dy::Float64
end

struct TabMass
    val::Float64
end

struct TabHealth
    health::Float64
end

struct TabTag end

struct TabAcc
    val::Float64
end

struct TabWrap{C} <: AbstractVector{C}
    v::Vector{C}
end

TabWrap{C}() where {C} = TabWrap{C}(Vector{C}())

Base.size(w::TabWrap) = size(w.v)
Base.getindex(w::TabWrap, i::Int) = w.v[i]
Base.setindex!(w::TabWrap, v, i::Int) = (w.v[i] = v)
Base.resize!(w::TabWrap, n::Int) = (resize!(w.v, n); w)
Base.push!(w::TabWrap, x) = (push!(w.v, x); w)
Base.sizehint!(w::TabWrap, n::Int) = (sizehint!(w.v, n); w)
Base.empty!(w::TabWrap) = (empty!(w.v); w)

@kernel function tab_move_kernel!(positions, velocities, dt)
    i = @index(Global)
    @inbounds positions[i] =
        TabPos(positions[i].x + velocities[i].dx * dt, positions[i].y + velocities[i].dy * dt)
end

@kernel function tab_heal_kernel!(healths, amount)
    i = @index(Global)
    @inbounds healths[i] = TabHealth(healths[i].health + amount)
end

@kernel function tab_scatter_kernel!(positions, velocities)
    i = @index(Global)
    @inbounds velocities[i] = TabVel(positions[i].x, positions[i].y)
end

# All-pairs interactions across table boundaries.
@kernel function tab_allpairs_kernel!(positions, accelerations)
    i = @index(Global)
    n = length(positions)
    acc = 0.0
    @inbounds for j in 1:n
        i == j && continue
        acc += sign(positions[j].x - positions[i].x)
    end
    @inbounds accelerations[i] = acc
end

function _tab_query_columns(world::World, ::Type{C}) where {C}
    cols = Vector{C}()
    for (entities, columns...) in Query(world, (C,))
        append!(cols, columns[1])
    end
    return cols
end

@testset "FlatQuery on the :CPU back-end" begin
    backend = CPU()

    @testset "multiple tables, kernel writes and reads" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        for i in 1:5
            new_entity!(world, (TabPos(i, 2i), TabVel(1, 1)))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, 2 * (100 + i)), TabVel(1, 1), TabHealth(1)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test sprint(show, q) == "FlatQuery(entities=8, tables=2, comp_types=(TabPos, TabVel))"

        n = length(q)
        @test n == 8

        tab_move_kernel!(backend)(q[TabPos], q[TabVel], 0.5; ndrange = n)
        KernelAbstractions.synchronize(backend)

        expected = _tab_query_columns(world, TabPos)
        positions = q[TabPos]
        @test length(positions) == 8
        for i in eachindex(positions)
            @test positions[i] == expected[i]
        end

        reset!(world)
    end

    @testset "destructuring yields views in filter order" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        es = Entity[]
        for i in 1:5
            push!(es, new_entity!(world, (TabPos(i, 2i), TabVel(1, 1))))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1)))
        end

        positions, velocities = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(positions) == 8
        @test length(velocities) == 8
        @test positions[3] == TabPos(3, 6)
        @test positions[6] == TabPos(101, 1)
        @test velocities[8] == TabVel(1, 1)
        px, py = unpack(positions)
        @test px[3] == 3.0 && py[3] == 6.0

        positions, velocities, entities = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(entities) == 8
        @test entities[1] == es[1]
        @test entities[5] == es[5]
        @test length(positions) == 8 && length(velocities) == 8

        reset!(world)
    end

    @testset "flat query yields component views and entities" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        es = Entity[]
        for i in 1:5
            push!(es, new_entity!(world, (TabPos(i, 2i), TabVel(1, 1))))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test q isa FlatQuery

        positions, velocities = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(positions) == 8
        @test positions[3] == TabPos(3, 6)

        positions, velocities, entities = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(entities) == 8
        @test entities[1] == es[1]
        @test entities[5] == es[5]
        @test positions[6] == TabPos(101, 1)
        @test velocities[8] == TabVel(1, 1)

        # entity ids are exposed by type as well
        @test length(q[Entity]) == 8
        @test q[Entity][5] == es[5]

        # structural changes are picked up, entity views included
        e9 = new_entity!(world, (TabPos(9, 9), TabVel(1, 1)))
        positions, velocities, entities = q
        @test length(entities) == 9
        @test entities[9] == e9
        @test positions[9] == TabPos(9, 9)

        reset!(world)
    end

    @testset "host storages" begin
        backend = CPU()

        @testset "default Vector storage" begin
            world = World(TabPos, TabVel)
            for i in 1:5
                new_entity!(world, (TabPos(i, 2i), TabVel(1, 1)))
            end
            for i in 1:3
                new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1)))
            end

            q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
            positions, velocities, entities = q
            @test length(positions) == 8
            @test positions[3] == TabPos(3, 6)
            @test positions[6] == TabPos(101, 1)
            @test velocities[8] == TabVel(1, 1)

            tab_move_kernel!(backend)(positions, velocities, 0.5; ndrange = length(positions))
            expected = _tab_query_columns(world, TabPos)
            positions, velocities, entities = q
            for i in eachindex(positions)
                @test positions[i] == expected[i]
            end

            e9 = new_entity!(world, (TabPos(9, 9), TabVel(1, 1)))
            positions, velocities, entities = q
            @test length(positions) == 9
            @test positions[9] == TabPos(9, 9)
            @test entities[9] == e9

            reset!(world)
        end

        @testset "StructArray storage" begin
            world = World(TabPos => Storage(StructArray))
            for i in 1:4
                new_entity!(world, (TabPos(i, 2i),))
            end

            q = FlatQuery(world, Filter(world, (TabPos,)))
            positions = q[TabPos]
            @test positions[2] == TabPos(2, 4)
            x, y = unpack(positions)
            @test x == [1.0, 2.0, 3.0, 4.0]
            @test y == [2.0, 4.0, 6.0, 8.0]

            positions[1] = TabPos(9, 9)
            @test q[TabPos][1] == TabPos(9, 9)

            reset!(world)
        end

        @testset "custom storage" begin
            world = World(TabPos => Storage(TabWrap))
            for i in 1:3
                new_entity!(world, (TabPos(i, 2i),))
            end

            q = FlatQuery(world, Filter(world, (TabPos,)))
            positions = q[TabPos]
            @test positions[3] == TabPos(3, 6)
            positions[1] = TabPos(8, 8)
            @test q[TabPos][1] == TabPos(8, 8)

            reset!(world)
        end

        @testset "mixed GPU and host storages are rejected" begin
            world = World(TabPos => Storage(GPUVector, CPU()), TabVel => Storage(StructArray))
            new_entity!(world, (TabPos(1, 1), TabVel(1, 1)))
            @test_throws ArgumentError FlatQuery(world, Filter(world, (TabPos, TabVel)))

            reset!(world)
        end
    end

    @testset "reductions and bulk operations" begin
        backend = CPU()
        world = World(
            Float64 => Storage(GPUVector, CPU()),
            TabPos => Storage(GPUStructArray, CPU()),
            TabTag;
            initial_capacity = 2,
        )
        new_entity!(world, (1.0, TabPos(1, 1)))
        new_entity!(world, (2.0, TabPos(2, 2), TabTag()))

        scalars, positions = FlatQuery(world, Filter(world, (Float64, TabPos)))
        @test scalars.ntables == 2

        @test sum(scalars) == 3.0
        @test sum(x -> 2x, scalars) == 6.0
        @test sum(scalars; init = 10.0) == 13.0
        @test maximum(scalars) == 2.0
        @test minimum(scalars) == 1.0
        @test extrema(scalars) == (1.0, 2.0)
        @test count(x -> x > 1.5, scalars) == 1
        @test sum(x -> x.x, positions) == 3.0

        fill!(scalars, 5.0)
        @test collect(scalars) == [5.0, 5.0]

        dest = Vector{Float64}(undef, 2)
        copyto!(dest, scalars)
        @test dest == [5.0, 5.0]

        copyto!(scalars, [1.0, 2.0])
        @test collect(scalars) == [1.0, 2.0]

        world2 = World(Float64 => Storage(GPUVector, CPU()))
        new_entities!(world2, 2, (9.0,))
        dest2 = FlatQuery(world2, Filter(world2, (Float64,)))[Float64]
        copyto!(dest2, scalars)
        @test collect(dest2) == [1.0, 2.0]

        reset!(world)
        reset!(world2)
    end

    @testset "flat indexing spans all tables in order" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU()),
            TabTag,
            TabMass => Storage(GPUStructArray, CPU());
            initial_capacity = 2,
        )
        sizes = [3, 0, 7, 1, 12, 2]
        id = 0
        for (k, size) in enumerate(sizes)
            for _ in 1:size
                id += 1
                if k in (2, 4) # extra component -> separate archetypes
                    new_entity!(world, (TabPos(id, id), TabVel(id, id), TabTag(), TabMass(id)))
                else
                    new_entity!(world, (TabPos(id, id), TabVel(id, id), TabMass(id)))
                end
            end
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel, TabMass)))
        @test length(q) == 25

        positions = q[TabPos]
        velocities = q[TabVel]
        masses = q[TabMass]
        expected_pos = _tab_query_columns(world, TabPos)
        expected_vel = _tab_query_columns(world, TabVel)
        @test length(expected_pos) == 25
        for i in 1:25
            @test positions[i] == expected_pos[i]
            @test velocities[i] == expected_vel[i]
            @test masses.val[i] == Float64(expected_pos[i].x)
        end

        # row gather/destructuring on the flat struct array view
        @test positions[4] == TabPos(4.0, 4.0)
        let (a, b) = (positions[1], positions[2])
            @test a.x == 1.0 && b.y == 2.0
        end

        reset!(world)
    end

    @testset "all-pairs interaction across table boundaries" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabAcc => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        # two tables with entity values chosen so cross-table pairs matter
        for i in 1:4
            new_entity!(world, (TabPos(Float64(i), 0), TabVel(0, 0)))
        end
        for i in 1:4
            new_entity!(world, (TabPos(Float64(100 + i), 0), TabVel(0, 0)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel, TabAcc)))
        n = length(q)
        accs = q[TabAcc]
        tab_allpairs_kernel!(backend)(q[TabPos], accs; ndrange = n)
        KernelAbstractions.synchronize(backend)

        # brute-force expectation over all 8 entities, independent of tables
        all_pos = _tab_query_columns(world, TabPos)
        for i in 1:n
            acc = 0.0
            for j in 1:n
                i == j && continue
                acc += sign(all_pos[j].x - all_pos[i].x)
            end
            @test accs[i].val == acc
        end

        reset!(world)
    end

    @testset "refresh on structural changes" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU()),
            TabTag;
            initial_capacity = 2,
        )
        e1 = new_entity!(world, (TabPos(1, 1), TabVel(1, 1)))
        for i in 2:5
            new_entity!(world, (TabPos(i, i), TabVel(1, 1)))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1), TabHealth(1)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(q) == 8

        # growth of an existing table (forces column reallocation)
        for i in 1:4
            new_entity!(world, (TabPos(-i, -2i), TabVel(1, 1)))
        end
        @test length(q) == 12
        positions = q[TabPos]
        @test positions[9] == TabPos(-4, -8)

        # new archetype / table
        new_entity!(world, (TabPos(50, 50), TabVel(1, 1), TabTag()))
        @test length(q) == 13
        @test q[TabPos][13] == TabPos(50, 50)

        # removal swap-removes rows within tables
        remove_entity!(world, e1)
        @test length(q) == 12
        @test q[TabPos][1] == TabPos(-4, -8)

        # kernel still writes correctly after all changes
        tab_scatter_kernel!(backend)(q[TabPos], q[TabVel]; ndrange = length(q))
        KernelAbstractions.synchronize(backend)
        expected_vel = _tab_query_columns(world, TabVel)
        @test q[TabVel] == expected_vel

        reset!(world)
    end

    @testset "without filter and Filter constructor" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        for i in 1:5
            new_entity!(world, (TabPos(i, i), TabVel(1, 1)))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1), TabHealth(1)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel); without=(TabHealth,)))
        @test length(q) == 5
        @test q[TabPos][5] == TabPos(5, 5)

        filter = Filter(world, (TabPos, TabVel))
        q_f = FlatQuery(world, filter)
        @test length(q_f) == 8
        @test q_f[TabVel][8] == TabVel(1, 1)

        reset!(world)
    end

    @testset "registered filters use the cached table list" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        for i in 1:4
            new_entity!(world, (TabPos(i, i), TabVel(1, 1)))
        end
        for i in 1:2
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1), TabHealth(1)))
        end

        filter = Filter(world, (TabPos, TabVel); register=true)
        q = FlatQuery(world, filter)
        @test length(q) == 6

        new_entity!(world, (TabPos(9, 9), TabVel(1, 1)))
        @test length(q) == 7
        @test q[TabPos][5] == TabPos(9, 9)

        unregister!(world, filter)
        reset!(world)
    end

    @testset "relation targets filter tables within an archetype" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            Relation{ChildOf};
            initial_capacity = 2,
        )
        parent1 = new_entity!(world, ())
        parent2 = new_entity!(world, ())
        for i in 1:5
            new_entity!(world, (TabPos(i, i), TabVel(1, 1), ChildOf() => parent1))
        end
        for i in 1:3
            new_entity!(world, (TabPos(100 + i, i), TabVel(1, 1), ChildOf() => parent2))
        end

        batch1 = FlatQuery(world, Filter(world, (TabPos, TabVel, ChildOf => parent1)))
        @test length(batch1) == 5
        @test batch1[TabPos][5] == TabPos(5, 5)
        @test_throws ArgumentError batch1[ChildOf]

        batch2 = FlatQuery(world, Filter(world, (TabPos, TabVel, ChildOf => parent2)))
        @test length(batch2) == 3

        batch_all = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        @test length(batch_all) == 8

        reset!(world)
    end

    @testset "flat struct array view fields and scatter" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
            TabHealth => Storage(GPUVector, CPU());
            initial_capacity = 2,
        )
        for i in 1:6
            new_entity!(world, (TabPos(i, 2i), TabVel(0, 0)))
        end
        for i in 1:4
            new_entity!(world, (TabPos(100 + i, 2 * (100 + i)), TabVel(0, 0), TabHealth(1)))
        end

        q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        positions = q[TabPos]
        velocities = q[TabVel]

        # property access yields flat field views
        @test positions.x isa Ark.FlatVectorView
        @test length(positions.x) == 10
        @test positions.x[9] == 103.0
        @test_throws ErrorException positions.z

        # unpack
        fields = unpack(positions)
        @test fields.x isa Ark.FlatVectorView && fields.y isa Ark.FlatVectorView
        @test fields.y[3] == 6.0

        # kernel writing through field arrays
        tab_scatter_kernel!(backend)(positions, velocities; ndrange = length(q))
        KernelAbstractions.synchronize(backend)
        @test q[TabVel][1] == TabVel(1.0, 2.0)
        @test q[TabVel][9] == TabVel(103.0, 206.0)

        # whole-value scatter
        positions[2] = TabPos(-1, -2)
        @test positions[2] == TabPos(-1, -2)

        reset!(world)
    end

    @testset "empty batches" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
        )
        new_entity!(world, (TabPos(1, 1), TabVel(1, 1)))

        q = FlatQuery(world, Filter(world, (TabPos,); without=(TabVel,)))
        @test length(q) == 0
        @test length(q[TabPos]) == 0
        @test sprint(show, q) == "FlatQuery(entities=0, tables=0, comp_types=(TabPos))"

        # kernels with ndrange 0 are a no-op
        tab_heal_kernel!(backend)(q[TabPos], 1.0; ndrange = length(q))
        KernelAbstractions.synchronize(backend)

        reset!(world)
    end

    @testset "argument errors" begin
        world = TestWorld(
            TabPos,
            TabVel => Storage(GPUVector, CPU()),
        )
        new_entity!(world, (TabPos(1, 1), TabVel(1, 1)))

        @test_throws ArgumentError FlatQuery(world, Filter(world, (TabPos, TabVel)))
        filter_opt = Filter(world, (TabPos,); optional=(TabVel,))
        @test_throws ArgumentError FlatQuery(world, filter_opt)

        q = FlatQuery(world, Filter(world, (TabVel,)))
        @test_throws ArgumentError q[TabPos]

        reset!(world)
    end

    @testset "bounds checking" begin
        world = TestWorld(
            TabPos => Storage(GPUStructArray, CPU()),
            TabVel => Storage(GPUVector, CPU()),
        )
        for i in 1:4
            new_entity!(world, (TabPos(i, i), TabVel(1, 1)))
        end
        q = FlatQuery(world, Filter(world, (TabPos, TabVel)))
        positions = q[TabPos]
        @test_throws BoundsError positions[0]
        @test_throws BoundsError positions[5]
        @test_throws BoundsError (positions.x)[5]
    end
end
