
@testset "StructArray basic functionality" begin
    a = StructArray(Position)

    @test isa(a.x, Vector{Float64})
    @test isa(a.y, Vector{Float64})
    @test isa(getfield(a, :_components).x, Vector{Float64})
    @test isa(getfield(a, :_components).y, Vector{Float64})

    push!(a, Position(1, 2))

    @test length(a) == 1
    @test size(a) == (1,)
    @test length(getfield(a, :_components).x) == 1
    @test length(getfield(a, :_components).y) == 1
    @test a[1] == Position(1, 2)

    a[1] = Position(3, 4)
    @test a[1] == Position(3, 4)

    push!(a, Position(5, 6))
    @test length(a) == 2

    pop!(a)
    @test length(a) == 1

    fill!(a, Position(99, 99))
    for pos in a
        @test pos == Position(99, 99)
    end
end

@testset "StructArray iteration" begin
    a = StructArray(Position)

    resize!(a, 10)
    @test length(a) == 10

    for i in 1:10
        a[i] = Position(i, i)
    end

    count = 0
    for i in eachindex(a)
        @test a[i] == Position(i, i)
        count += 1
    end
    @test count == 10

    for pos in a
        @test isa(pos, Position)
    end
    for (i, pos) in enumerate(a)
        @test a[i] == Position(i, i)
    end
end

@testset "StructArray misc functions" begin
    a = StructArray(Position)
    resize!(a, 10)

    @test Base.firstindex(a) == 1
    @test Base.lastindex(a) == 10

    @test Base.eltype(StructArray{Position}) == Position
    @test Base.IndexStyle(StructArray{Position}) == IndexLinear()
end

@testset "StructArray no fields" begin
    @test_throws(
        "StructArray storage not allowed for components without fields",
        StructArray(LabelComponent)
    )
end

@testset "StructArray unwrap" begin
    a = StructArray(Position)

    x, y = getfield(a, :_components)
    @test isa(x, Vector{Float64})
    @test isa(y, Vector{Float64})
end

@testset "StructArray type" begin
    tp = _StructArray_type(Position)
    @test tp == StructArray{Position,@NamedTuple{x::Vector{Float64}, y::Vector{Float64}},2}
end

@testset "Vector view" begin
    # template for tests below to ensure that StructArray views behave like Vector views
    a = Vector{Position}()
    for i in 1:10
        push!(a, Position(i, i))
    end

    v = view(a, 5:10)
    @test v[1] == Position(5, 5)
    v[1] = Position(99, 99)
    @test v[1] == Position(99, 99)

    @test length(v) == 6
    @test size(v) == (6,)
    @test firstindex(v) == 1
    @test lastindex(v) == 6
    @test eachindex(v) == 1:6
end

@testset "StructArray view" begin
    a = StructArray(Position)
    for i in 1:10
        push!(a, Position(i, i))
    end

    v = view(a, 5:10)
    x, y = v._components
    @test isa(x, SubArray{Float64})
    @test isa(y, SubArray{Float64})
    x, y = unpack(v)
    @test isa(x, SubArray{Float64})
    @test isa(y, SubArray{Float64})

    @test v[1] == Position(5, 5)
    v[1] = Position(99, 99)
    @test v[1] == Position(99, 99)

    @test length(v) == 6
    @test size(v) == (6,)
    @test firstindex(v) == 1
    @test lastindex(v) == 6
    @test eachindex(v) == 1:6

    @test Base.eltype(typeof(v)) == Position
    @test Base.IndexStyle(typeof(v)) == IndexLinear()

    fill!(v, Position(99, 99))
    for pos in v
        @test pos == Position(99, 99)
    end
end

@testset "StructArray show" begin
    a = StructArray(Position)
    for i in 1:11
        push!(a, Position(i, i))
    end

    @test string(view(a, :)) ==
          "11-element StructArrayView(x::SubArray{Float64}, y::SubArray{Float64}) with eltype Position
 Position(1.0, 1.0)
 Position(2.0, 2.0)
 Position(3.0, 3.0)
 Position(4.0, 4.0)
 Position(5.0, 5.0)
 Position(6.0, 6.0)
 Position(7.0, 7.0)
 Position(8.0, 8.0)
 Position(9.0, 9.0)
 Position(10.0, 10.0)
 Position(11.0, 11.0)
"

    a = StructArray(Position)
    for i in 1:12
        push!(a, Position(i, i))
    end

    @test string(view(a, :)) ==
          "12-element StructArrayView(x::SubArray{Float64}, y::SubArray{Float64}) with eltype Position
 Position(1.0, 1.0)
 Position(2.0, 2.0)
 Position(3.0, 3.0)
 Position(4.0, 4.0)
 Position(5.0, 5.0)
 ⋮
 Position(8.0, 8.0)
 Position(9.0, 9.0)
 Position(10.0, 10.0)
 Position(11.0, 11.0)
 Position(12.0, 12.0)
"
end
