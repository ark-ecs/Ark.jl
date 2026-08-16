
@testset "GPUVector components" begin
    w = TestWorld(
        A => Storage(GPUVector{:CPU}),
        B => Storage(GPUVector{:CPU}),
        Relation{C} => Storage(GPUVector{:CPU}),
    )
    e1 = new_entity!(w, (A(2.0), B(2.0)))
    @test get_components(w, e1, (A, B)) == (A(2.0), B(2.0))
    e2 = new_entity!(w, (A(2.0), B(2.0), C() => e1))
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
    add_components!(w, e2, (A(2.0), C() => e1))
    @test has_components(w, e2, (A, C)) == true
    er, = get_relations(w, e2, (C,))
    @test er == e1
    add_components!(w, e3, (C() => e2,))
    @test length(es) == 10
    set_relations!(w, e3, (C => er,))

    remove_entity!(w, e2)
    @test is_alive(w, e1) == true
    @test is_alive(w, e2) == false

    new_entities!(w, 1, (A(2.0), B(2.0)))
    new_entities!(w, 1, (A(2.0), B(2.0), C() => er))
    new_entities!(w, 2, (A, B)) do (entities, as, bs)
        for i in eachindex(as)
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

@testset "GPUVector CPU back-end" begin
    @test _gpuvector_type(Int, Val{:CPU}()) == Vector{Int}
    @test _gpuvector_type(Position, Val{:CPU}()) == Vector{Position}
    @test_throws MethodError _gpuvector_type(Int, Val{:V}())

    gv = GPUVector{:CPU,Int,_gpuvector_type(Int, Val{:CPU}())}()
    @test gv isa GPUVector{:CPU,Int,Vector{Int}}
    resize!(gv, 3)
    copyto!(gv, 1, [1, 2, 3], 1, 3)

    @test _gpuvector_hostwrap(gv.mem) === gv.mem
    @test_throws ArgumentError _gpuvector_hostwrap(1:3)

    w = TestWorld(A => Storage(GPUVector{:CPU}))
    new_entity!(w, (A(1.0),))
    @test _storage_from_component(w, A) == GPUVector{:CPU,A,Vector{A}}
end

@testset "GPUVectorView" begin
    gv = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(gv, 5)
    copyto!(gv, 1, [1, 2, 3, 4, 5], 1, 5)

    v = _gpuvector_view(gv, 2:4)
    @test typeof(v) == _gpuvectorview_type(typeof(gv))
    @test v isa GPUVectorView{:CPU,Int}
    @test eltype(v) == Int
    @test size(v) == (3,)
    @test length(v) == 3
    @test parent(v) === gv
    @test v == [2, 3, 4]
    @test v[1] == 2

    v[1] = 20
    @test v[1] == 20
    @test gv[2] == 20

    @test IndexStyle(typeof(v)) == IndexLinear()
    @test IndexStyle(typeof(gv)) == IndexLinear()

    @test_throws MethodError _gpuvectorview_type(Position, Val{:V}())
end

@testset "GPUVectorView adapts to the device view" begin
    gv = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(gv, 5)
    copyto!(gv, 1, [1, 2, 3, 4, 5], 1, 5)

    v = _gpuvector_view(gv, 2:4)

    dv = Adapt.adapt(nothing, v)
    @test dv isa SubArray
    @test parent(dv) === gv.mem
    @test dv == [2, 3, 4]

    dv[1] = 20
    @test gv[2] == 20
    @test v[1] == 20
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

    sizehint!(gv, 1000)
    @test length(gv) == 100

    empty!(gv)
    @test length(gv) == 0
    @test_throws ArgumentError pop!(gv)

    resize!(gv, 100)
    gv2 = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(gv2, length(gv))
    unsafe_copyto!(gv2, 1, gv, 1, length(gv))
    @test gv2[1:length(gv)] == gv[1:length(gv)]
end

@testset "GPUVector copyto!" begin
    src = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(src, 3)
    copyto!(src, 1, [1, 2, 3], 1, 3)
    @test src == [1, 2, 3]

    dest = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(dest, 5)
    fill!(dest.host, 0)

    copyto!(dest, 2, src, 1, 3)
    @test dest == [0, 1, 2, 3, 0]

    copyto!(dest, 1, src, 2, 2)
    @test dest == [2, 3, 2, 3, 0]
end

@testset "GPUVector copyto! bounds" begin
    src = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(src, 4)
    copyto!(src, 1, [1, 2, 3, 4], 1, 4)

    dest = GPUVector{:CPU,Int,Vector{Int}}()
    resize!(dest, 2)
    sizehint!(dest, 100)
    @test length(dest.mem) == 100
    @test length(dest) == 2

    copyto!(dest, 1, src, 1, 2)
    @test dest[1] == 1 && dest[2] == 2

    @test_throws BoundsError copyto!(dest, 1, src, 1, 3)
    @test_throws BoundsError copyto!(dest, 2, src, 1, 2)
    @test_throws BoundsError copyto!(dest, 1, [1, 2, 3], 1, 3)
    @test_throws BoundsError copyto!(dest, 0, src, 1, 1)
    @test_throws ArgumentError copyto!(dest, 1, src, 1, -1)

    copyto!(dest, 1, [7, 8], 1, 2)
    @test dest[1] == 7 && dest[2] == 8

    copyto!(dest, 100, src, 100, 0)
    @test dest[1] == 7 && dest[2] == 8
end

struct _TestGPUDevice end
Ark._gpuvector_ordinal(::_TestGPUDevice) = 1

@testset "GPUVector device selection" begin
    @test _gpuvector_device(Val{:CPU}()) === nothing
    @test _gpuvector_withdev(() -> 42, nothing) == 42

    @test _gpuvector_type(Int, Val{:CPU}()) == Vector{Int}
    @test _gpuvector_type(Int, Val{_GPUDevice{:CPU, 0}}()) == Vector{Int}
    @test_throws MethodError _gpuvector_type(Int, Val{(:CPU, 0)}())
    @test_throws ArgumentError _gpuvector_device(Val{_GPUDevice{:CPU, 0}}())
    @test_throws ArgumentError _gpuvector_device(Val{_GPUDevice{:OpenCL, 0}}())

    @test_throws ArgumentError TestWorld(A => Storage(GPUVector{:CPU}, _TestGPUDevice()))
    @test_throws ArgumentError TestWorld(A => Storage(GPUStructArray{:CPU}, _TestGPUDevice()))
end

struct _TestRuntimeBackend end
Ark._gpuvector_type(::Type{T}, ::Val{:RUNTIME}) where {T} = Vector{T}

@testset "GPU back-end registered at runtime (world age)" begin
    w = TestWorld(A => Storage(GPUVector{:RUNTIME}))
    new_entity!(w, (A(1.0),))
    @test collect(Query(w, (A,)))[1][2][1] == A(1.0)

    w = TestWorld(A => Storage(GPUStructArray{:RUNTIME}))
    new_entity!(w, (A(2.0),))
    @test collect(Query(w, (A,)))[1][2][1] == A(2.0)

    @test_throws ArgumentError TestWorld(A => Storage(GPUVector{:RUNTIME}, _TestGPUDevice()))
end

@testset "GPUVector device normalization" begin
    s = Storage(GPUVector{:CPU}, _TestGPUDevice())
    @test s == Storage{GPUVector{_GPUDevice{:CPU, 1}}}
    s = Storage(GPUStructArray{:CPU}, _TestGPUDevice())
    @test s == Storage{GPUStructArray{_GPUDevice{:CPU, 1}}}

    @test_throws ArgumentError Storage(GPUVector{:CPU}, :unknown_device)
    @test_throws ArgumentError Storage(GPUVector{:CPU,Int,Vector{Int}}, _TestGPUDevice())
    @test_throws ArgumentError Storage(Vector, _TestGPUDevice())
end
