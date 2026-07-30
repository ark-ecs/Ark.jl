
@testset "Entity is_zero" begin
    world = TestWorld()

    @test is_zero(zero_entity) == true
    @test is_zero(_new_entity(1, 0)) == true

    entity = new_entity!(world, ())
    @test is_zero(entity) == false
end

@testset "Entities interface tests" begin
    col = _new_entities_column()
    push!(col._data, _new_entity(1, 0))
    push!(col._data, _new_entity(2, 0))
    push!(col._data, _new_entity(3, 0))

    # Test getindex
    @test col[1] == _new_entity(1, 0)
    @test col[3] == _new_entity(3, 0)

    # Test length
    @test length(col) == 3

    # Test eachindex
    indices = collect(eachindex(col))
    @test indices == [1, 2, 3]

    # Test enumerate
    values = [(i, v) for (i, v) in enumerate(col)]
    @test values == [(1, _new_entity(1, 0)), (2, _new_entity(2, 0)), (3, _new_entity(3, 0))]

    # Test iteration
    collected = [v for v in col]
    @test collected == [_new_entity(1, 0), _new_entity(2, 0), _new_entity(3, 0)]

    @test firstindex(col) == 1
    @test lastindex(col) == 3
    @test eltype(col) == Entity
    @test size(col) == (length(col),)
    @test IndexStyle(col) == IndexLinear()
end

@testset "Entities show" begin
    col = _new_entities_column()
    for i in 1:11
        push!(col._data, _new_entity(i, 0))
    end
    @test string(col) ==
          "Entities[Entity(1, 0), Entity(2, 0), Entity(3, 0), Entity(4, 0), Entity(5, 0), " *
          "Entity(6, 0), Entity(7, 0), Entity(8, 0), Entity(9, 0), Entity(10, 0), Entity(11, 0)]"

    push!(col._data, _new_entity(12, 0))
    @test string(col) ==
          "Entities[Entity(1, 0), Entity(2, 0), Entity(3, 0), Entity(4, 0), Entity(5, 0), " *
          "…, Entity(8, 0), Entity(9, 0), Entity(10, 0), Entity(11, 0), Entity(12, 0)]"
end
