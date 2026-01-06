
@testset "GPUSyncStructArray interface" begin
    w = World(
        A => Storage{GPUSyncStructArray{Array}},
        B => Storage{GPUSyncStructArray{Array}},
        C,
    )
    e1 = new_entity!(w, (A(0.0), B(0.0)))
    @test get_components(w, e1, (A, B)) == (A(0.0), B(0.0))
    e2 = new_entity!(w, (A(0.0), B(0.0), C()); relations=(C => e1,))
    @test get_components(w, e2, (A, B, C)) == (A(0.0), B(0.0), C())
    e3 = copy_entity!(w, e1)
    @test e1 != e2 && e2 != e3

    es = Entity[]
    evs = (OnAddComponents, OnRemoveComponents)
    for ev in evs
        for t in ((A,), (B,), (C,), (A, B), (A, C), (B, C), (A, B, C))
            observe!(e -> push!(es, e), w, ev, t)
        end
    end
    evs2 = (OnCreateEntity, OnRemoveEntity)
    for ev in evs2
        observe!(e -> push!(es, e), w, ev)
    end
    evs3 = (OnAddRelations, OnRemoveRelations)
    for ev in evs3
        observe!(e -> push!(es, e), w, ev, (C,))
    end
    @test isempty(es) == true

    a, b, c = get_components(w, e2, (A, B, C))
    set_components!(w, e2, (A(a.x + 1.0), B(b.x + 1.0), c))
    @test length(es) == 0
    remove_components!(w, e2, (A, C))
    @test get_components(w, e2, (B,)) == (B(1.0),)
    @test has_components(w, e2, (A, C)) == false
    @test length(es) == 4
    add_components!(w, e2, (A(0.0), C()); relations=(C => e1,))
    @test has_components(w, e2, (A, C)) == true
    er, = get_relations(w, e2, (C,))
    @test er == e1
    add_components!(w, e3, (C(),); relations=(C => e2,))
    @test length(es) == 10
    set_relations!(w, e3, (C => er,))

    remove_entity!(w, e2)
    @test is_alive(w, e1) == true
    @test is_alive(w, e2) == false

    new_entities!(w, 1, (A(0.0), B(0.0)))
    new_entities!(w, 1, (A(0.0), B(0.0), C()); relations=(C => er,))
    remove_entity!(w, er)
    @test isempty(collect(Query(w, (A, B)))) == false
    @test isempty(collect(Query(w, (A, B, C)))) == false
    remove_entities!(w, Filter(w, (A, B)))
    remove_entities!(w, Filter(w, (A, B, C)))
    @test isempty(collect(Query(w, (A, B)))) == true
    reset!(w)
end

@testset "GPUSyncStructArray gpuviews" begin
    w = World(
        Position => Storage{GPUSyncStructArray{Array}},
        Velocity => Storage{GPUSyncStructArray{Array}},
    )
    new_entities!(w, 10, (Position(1.0, 2.0), Velocity(0.1, 0.2)))

    for (entities, positions, velocities) in Query(w, (Position, Velocity))
        x, y = gpuviews(positions)
        dx, dy = gpuviews(velocities; readonly=true)
        @test length(x) == 10
        @test x[1] == 1.0
        @test y[1] == 2.0
        @test dx[1] == 0.1
        @test dy[1] == 0.2
    end
    reset!(w)
end

@testset "GPUSyncStructArray internals" begin
    gsa = GPUSyncStructArray{Position,_StructArray_type(Position),_GPUStructArray_type(Array, Position)}()
    @test length(gsa) == 0

    push!(gsa, Position(1.0, 2.0))
    @test length(gsa) == 1
    @test gsa[1] == Position(1.0, 2.0)

    resize!(gsa, 10)
    @test length(gsa) == 10

    gsa[1] = Position(3.0, 4.0)
    @test gsa[1] == Position(3.0, 4.0)
    @test gsa.sync_cpu == true
    @test gsa.sync_gpu == false

    views = gpuviews(gsa)
    @test gsa.sync_cpu == false
    @test gsa.sync_gpu == true
    @test length(views) == 2
    @test views[1][1] == 3.0
    @test views[2][1] == 4.0

    gsa[1] = Position(5.0, 6.0)
    @test gsa[1] == Position(5.0, 6.0)
    @test gsa.sync_cpu == true
    @test gsa.sync_gpu == false
end

@testset "_GPUStructArray internals" begin
    gsa = _GPUStructArray(Array, Position, 10)
    @test length(gsa) == 10

    tp = _GPUStructArray_type(Array, Position)
    @test tp == _GPUStructArray{Position,@NamedTuple{x::Array{Float64, 1}, y::Array{Float64, 1}},2}
end
