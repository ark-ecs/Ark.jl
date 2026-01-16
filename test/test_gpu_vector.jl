
@testset "GPUVector components" begin
    w = World(
        A => Storage{GPUVector{:CPU}},
        B => Storage{GPUVector{:CPU}},
        C => Storage{GPUVector{:CPU}},
    )
    e1 = new_entity!(w, (A(2.0), B(2.0)))
    @test get_components(w, e1, (A, B)) == (A(2.0), B(2.0))
    e2 = new_entity!(w, (A(2.0), B(2.0), C()); relations=(C => e1,))
    @test get_components(w, e2, (A, B, C)) == (A(2.0), B(2.0), C())
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
    @test get_components(w, e2, (B,)) == (B(3.0),)
    @test has_components(w, e2, (A, C)) == false
    @test length(es) == 4
    add_components!(w, e2, (A(2.0), C()); relations=(C => e1,))
    @test has_components(w, e2, (A, C)) == true
    er, = get_relations(w, e2, (C,))
    @test er == e1
    add_components!(w, e3, (C(),); relations=(C => e2,))
    @test length(es) == 10
    set_relations!(w, e3, (C => er,))

    remove_entity!(w, e2)
    @test is_alive(w, e1) == true
    @test is_alive(w, e2) == false

    new_entities!(w, 1, (A(2.0), B(2.0)))
    new_entities!(w, 1, (A(2.0), B(2.0), C()); relations=(C => er,))
    new_entities!(w, 2, (A, B)) do (entities, as, bs)
        for i in eachindex(entities)
            as[i] = A(2.0)
            bs[i] = B(2.0)
        end
    end

    remove_entity!(w, er)
    @test isempty(collect(Query(w, (A,); with=(B,)))) == false
    @test isempty(collect(Query(w, (A, B, C)))) == false

    @test collect(Query(w, (A, B)))[1][2][1] == (A(2.0))
    for (_, as, cs) in Query(w, (A,); optional=(C,))
        @test as != nothing
    end
    remove_entities!(w, Filter(w, (A, B)))
    remove_entities!(w, Filter(w, (A, B, C)))
    @test isempty(collect(Query(w, (A, B)))) == true
    reset!(w)
end

@testset "GPUVector interface" begin
    gv = GPUVector{:CPU,Int,Vector{Int}}()
    @test length(gv) == 0
    resize!(gv, 100)
    @test length(gv) == 100

    copyto!(gv, 1, fill(1, 100), 1, 100)
    @test length(unique(gv)) == 1 && unique(gv)[1] == 1
    @test typeof(similar(gv)) == GPUVector{:CPU,Int,Vector{Int}}
    @test typeof(similar(gv, Int, (1,))) == GPUVector{:CPU,Int,Vector{Int}}

    gv[1] = 2
    @test gv[1] == 2
    gv[1] = 1
    @test gv[1] == 1

    pop!(gv)
    @test length(gv) == 99

    push!(gv, 10)
    @test gv[100] == 10
    @test length(gv) == 100

    @test_throws MethodError _gpuvectorview_type(Position, Val{:V}())
end
