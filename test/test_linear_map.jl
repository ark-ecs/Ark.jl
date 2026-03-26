using Test

# Helper key type to force collisions and stress probing/backshift-delete logic
struct BadHashKey
    x::Int
end

Base.:(==)(a::BadHashKey, b::BadHashKey) = a.x == b.x
Base.hash(::BadHashKey, h::UInt) = hash(0xBADC0DE, h)

@testset "_Linear_Map init" begin
    d = _Linear_Map{_Mask{1},Int}()
    @test length(d) == 0

    d2 = _Linear_Map{_Mask{1},Float64}(5)
    @test length(d2.keys) == 8
    @test d2.max_load == floor(Int, 8 * _LOAD_FACTOR)
end

@testset "_Linear_Map basics" begin
    d = _Linear_Map{_Mask{1},Int}(16)
    key1 = _Mask{1}((0x123456789ABC,))
    key2 = _Mask{1}((0x987654321FED,))

    val1 = Base.get!(() -> 100, d, key1)
    @test val1 == 100
    @test length(d) == 1

    val1_existing = Base.get!(() -> 500, d, key1)
    @test val1_existing == 100
    @test length(d) == 1

    val2 = Base.get!(() -> 200, d, key2)
    @test val2 == 200
    @test length(d) == 2
end

@testset "_Linear_Map getindex and get" begin
    d = _Linear_Map{_Mask{1},String}(16)
    k1 = _Mask{1}((UInt64(1),))
    Base.get!(() -> "Value1", d, k1)

    @test d[k1] == "Value1"

    k_missing = _Mask{1}((UInt64(999),))
    @test_throws KeyError d[k_missing]

    @test Base.get(() -> "Default", d, k1) == "Value1"
    @test Base.get(() -> "Default", d, k_missing) == "Default"
end

@testset "_Linear_Map resizing" begin
    initial_size = 4
    d = _Linear_Map{_Mask{1},Int}(initial_size)

    k1 = _Mask{1}((UInt64(1),))
    Base.get!(() -> 1, d, k1)
    k2 = _Mask{1}((UInt64(2),))
    Base.get!(() -> 2, d, k2)
    k3 = _Mask{1}((UInt64(3),))
    Base.get!(() -> 3, d, k3)

    @test length(d.keys) == 4
    @test d.count == 3

    k4 = _Mask{1}((UInt64(4),))
    Base.get!(() -> 4, d, k4)

    @test length(d.keys) == 8
    @test d.count == 4

    @test d[k1] == 1
    @test d[k2] == 2
    @test d[k3] == 3
    @test d[k4] == 4
end

@testset "_Linear_Map get!" begin
    d = _Linear_Map{_Mask{1},Int}(8)

    keys = [_Mask{1}((UInt64(i),)) for i in 1:6]

    for (i, k) in enumerate(keys)
        Base.get!(() -> i, d, k)
    end

    @test length(d) == 6

    for (i, k) in enumerate(keys)
        @test d[k] == i
    end
end

@testset "_Linear_Map setindex!, haskey, and get defaults" begin
    d = _Linear_Map{Int,String}(4)

    @test !haskey(d, 1)
    @test get(d, 1, "missing") == "missing"
    @test get(() -> "lazy-missing", d, 1) == "lazy-missing"

    d[1] = "one"
    @test haskey(d, 1)
    @test d[1] == "one"
    @test length(d) == 1

    # updating an existing key should not increase length
    d[1] = "ONE"
    @test d[1] == "ONE"
    @test length(d) == 1

    d[2] = "two"
    @test haskey(d, 2)
    @test d[2] == "two"
    @test length(d) == 2

    # get with concrete default should not insert
    @test get(d, 99, "fallback") == "fallback"
    @test !haskey(d, 99)
    @test length(d) == 2
end

@testset "_Linear_Map get/get! with Type" begin
    d1 = _Linear_Map{Int,Int}(4)
    @test get(() -> 0, d1, 10) == 0
    @test !haskey(d1, 10)

    @test get!(() -> 0, d1, 10) == 0
    @test haskey(d1, 10)
    @test d1[10] == 0

    d2 = _Linear_Map{Int,Vector{Int}}(4)
    v = get!(Vector{Int}, d2, 1)
    @test v isa Vector{Int}
    @test isempty(v)

    push!(v, 42)
    @test get!(Vector{Int}, d2, 1) === v
    @test d2[1] == [42]
    @test length(d2) == 1
end

@testset "_Linear_Map delete! and pop!" begin
    d = _Linear_Map{Int,String}(8)
    d[1] = "one"
    d[2] = "two"
    d[3] = "three"

    @test delete!(d, 2) === d
    @test !haskey(d, 2)
    @test length(d) == 2
    @test d[1] == "one"
    @test d[3] == "three"

    # deleting a missing key is a no-op
    @test delete!(d, 999) === d
    @test length(d) == 2

    @test pop!(d, 1) == "one"
    @test !haskey(d, 1)
    @test length(d) == 1

    @test_throws KeyError pop!(d, 1)
end

@testset "_Linear_Map collision handling and backshift delete" begin
    d = _Linear_Map{BadHashKey,Int}(8)

    k1 = BadHashKey(1)
    k2 = BadHashKey(2)
    k3 = BadHashKey(3)
    k4 = BadHashKey(4)

    d[k1] = 10
    d[k2] = 20
    d[k3] = 30
    d[k4] = 40

    @test length(d) == 4
    @test d[k1] == 10
    @test d[k2] == 20
    @test d[k3] == 30
    @test d[k4] == 40

    # remove from middle of probe chain
    delete!(d, k2)
    @test !haskey(d, k2)
    @test length(d) == 3

    # remaining keys must still be reachable after backshift
    @test d[k1] == 10
    @test d[k3] == 30
    @test d[k4] == 40

    # inserting after a backshifted delete should still work
    k5 = BadHashKey(5)
    d[k5] = 50
    @test d[k5] == 50
    @test length(d) == 4

    # pop! should also work correctly in a collision-heavy table
    @test pop!(d, k3) == 30
    @test !haskey(d, k3)
    @test d[k1] == 10
    @test d[k4] == 40
    @test d[k5] == 50
end

@testset "_Linear_Map iteration, keys, and values" begin
    d = _Linear_Map{Int,String}(8)
    d[10] = "ten"
    d[20] = "twenty"
    d[30] = "thirty"

    @test length(d) == 3
    @test length(keys(d)) == 3
    @test length(values(d)) == 3

    got = Dict(collect(d))
    @test got == Dict(10 => "ten", 20 => "twenty", 30 => "thirty")

    @test Set(collect(keys(d))) == Set([10, 20, 30])
    @test Set(collect(values(d))) == Set(["ten", "twenty", "thirty"])

    # direct iterate coverage
    first_item = iterate(d)
    @test first_item !== nothing

    first_key = iterate(keys(d))
    @test first_key !== nothing

    first_val = iterate(values(d))
    @test first_val !== nothing
end

@testset "_Linear_Map empty! and reuse" begin
    d = _Linear_Map{String,String}(4; zero_key = "<empty-key>", zero_value = "<empty-val>")
    d["a"] = "A"
    d["b"] = "B"

    @test length(d) == 2
    empty!(d)

    @test length(d) == 0
    @test iterate(d) === nothing
    @test iterate(keys(d)) === nothing
    @test iterate(values(d)) === nothing
    @test all(x -> x == 0x00, d.occupied)

    for i in eachindex(d.keys)
        @test d.keys[i] == "<empty-key>"
        @test d.vals[i] == "<empty-val>"
    end

    # map should still be usable after empty!
    d["c"] = "C"
    @test length(d) == 1
    @test d["c"] == "C"
end

@testset "_Linear_Map interface traits" begin
    d = _Linear_Map{Int,String}(4)
    ks = keys(d)
    vs = values(d)

    @test Base.IteratorSize(typeof(d)) isa Base.HasLength
    @test Base.IteratorSize(typeof(ks)) isa Base.HasLength
    @test Base.IteratorSize(typeof(vs)) isa Base.HasLength

    @test eltype(typeof(d)) == Pair{Int,String}
    @test eltype(typeof(ks)) == Int
    @test eltype(typeof(vs)) == String
end
