
@testset "_EntityPool constructor" begin
    initialCap = UInt32(10)
    pool = _EntityPool(initialCap)

    @test isa(pool, _EntityPool)
    @test length(pool.entities) == 1
    @test all(e -> e._gen == typemax(UInt32), pool.entities)
    @test pool.next == 0
end

@testset "_EntityPool logic" begin
    # Setup
    pool = _EntityPool(UInt32(10))  # creates 2 reserved entities

    @test length(pool.entities) == 1
    @test pool.next == 0

    @test _is_alive(pool, zero_entity) == false

    # Test _get_entity when no available entities
    e1 = _get_entity(pool)
    @test isa(e1, Entity)
    @test e1._id == 2
    @test e1._gen == 0
    @test length(pool.entities) == 2

    # Test _get_entity again
    e2 = _get_entity(pool)
    @test e2._id == 3
    @test e2._gen == 0
    @test length(pool.entities) == 3

    # Test _recycle with non-reserved entity
    _recycle(pool, e1)
    @test pool.next == e1._id
    @test pool.entities[e1._id]._gen == e1._gen + 1

    # Test _get_entity now uses recycled entity
    e3 = _get_entity(pool)
    @test e3._id == e1._id
    @test e3._gen == e1._gen + 1
    @test pool.next == 0

    # Test _alive
    @test _is_alive(pool, e2) == true
    @test _is_alive(pool, e3) == true
    @test _is_alive(pool, e1) == false  # old generation

    # Test _recycle throws on reserved entity
    @test_throws "ArgumentError: can't recycle the reserved zero entity" _recycle(pool, zero_entity)
end

@testset "_QueryPool logic" begin
    pool = _QueryPool(UInt32(2))

    @test length(pool.queries) == 0
    @test pool.next == 0
    @test pool._lock isa ReentrantLock

    q1 = _get_query(pool)
    @test q1._id == 1
    @test q1._gen == UInt64(0)
    @test q1._gen isa UInt64
    @test _is_alive(pool, q1) == true

    @test _recycle(pool, q1) == true
    @test _is_alive(pool, q1) == false
    @test pool.next == q1._id
    @test pool.queries[q1._id]._gen == UInt64(1)
    @test _recycle(pool, q1) == false

    q2 = _get_query(pool)
    @test q2._id == q1._id
    @test q2._gen == UInt64(1)
    @test q2._gen isa UInt64
    @test _is_alive(pool, q2) == true
    @test _is_alive(pool, q1) == false

    q3 = _get_query(pool)
    @test q3._id == 2
    @test q3._gen == UInt64(0)
    @test _is_alive(pool, q3) == true
end
