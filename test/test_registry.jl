
@testset "ComponentRegistry Tests" begin
    registry = _ComponentRegistry()

    # Register new types
    id_int = _register_component!(registry, Int, false)
    id_float = _register_component!(registry, Float64, false)
    id_pos = _register_component!(registry, Position, false)

    # Check that IDs are Int and unique
    @test isa(id_int, Int)
    @test isa(id_float, Int)
    @test isa(id_pos, Int)
    @test id_int != id_float != id_pos

    @test _get_id!(registry, Int) == id_int

    @test_throws "ArgumentError: component type String is not registered" _get_id!(registry, String)
end
