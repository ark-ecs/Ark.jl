
@testset "_EntityPool constructor" begin
    initialCap = UInt32(10)
    pool = _EntityPool(initialCap)

    @test isa(pool, _EntityPool)
    @test length(pool.gens) == 1
    @test pool.gens[1] == typemax(UInt32)
    @test isempty(pool.free)
end

@testset "_EntityPool logic" begin
    # Setup
    pool = _EntityPool(UInt32(10))

    @test length(pool.gens) == 1
    @test isempty(pool.free)

    @test _is_alive(pool, zero_entity) == false

    # Test _get_entity when no available entities
    e1 = _get_entity(pool)
    @test isa(e1, Entity)
    @test e1._id == 2
    @test e1._gen == 0
    @test length(pool.gens) == 2
    @test isempty(pool.free)

    # Test _get_entity again
    e2 = _get_entity(pool)
    @test e2._id == 3
    @test e2._gen == 0
    @test length(pool.gens) == 3

    # Test _recycle with non-reserved entity
    _recycle(pool, e1)
    @test pool.free == [e1._id]
    @test pool.gens[e1._id] == e1._gen + 1

    # Test _get_entity now uses recycled entity
    e3 = _get_entity(pool)
    @test e3._id == e1._id
    @test e3._gen == e1._gen + 1
    @test isempty(pool.free)

    # Test _alive
    @test _is_alive(pool, e2) == true
    @test _is_alive(pool, e3) == true
    @test _is_alive(pool, e1) == false  # old generation

    # Test _recycle throws on reserved entity
    @test_throws "ArgumentError: can't recycle the reserved zero entity" _recycle(pool, zero_entity)
end

@testset "_EntityPool pending entities" begin
    pool = _EntityPool(UInt32(10))

    e1 = _get_entity(pool)
    pending = _get_pending_entity(pool)

    @test pending._gen == e1._gen + 1
    @test _is_alive(pool, e1) == true
    @test _is_alive(pool, pending) == false

    _activate_entity!(pool, pending)
    @test _is_alive(pool, pending) == true

    _recycle(pool, pending)
    @test _is_alive(pool, pending) == false
end
