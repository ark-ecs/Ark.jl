using Test
using Ark

@testset "Unchecked API" begin
    # Setup world
    struct Health
        value::Int
    end
    struct Position
        x::Float64
        y::Float64
    end
    struct Relation <: Ark.Relationship end

    world = World(Health, Position, Relation)

    @testset "get_components unchecked" begin
        e = new_entity!(world, (Health(10),))
        
        # Normal access
        (h,) = get_components(world, e, (Health,))
        @test h.value == 10

        # Unchecked access
        (h2,) = get_components(world, e, (Health,); unchecked=true)
        @test h2.value == 10

        # Remove entity to make it dead
        remove_entity!(world, e)
        @test !is_alive(world, e)

        # Checked access throws
        @test_throws ArgumentError get_components(world, e, (Health,))

        # Unchecked access (unsafe, but testing API accepts it)
        # Note: Depending on implementation, this might return garbage or work if memory not reused.
        # We just test it doesn't throw the "dead entity" error immediately.
        # Because we recently removed it, data might still be there or cleared.
        # But if we access unchecked, we skip the is_alive check.
        # However, it involves accessing internal storage.
        # If the index is still valid (pointing to a removed slot or recycled one), it assumes valid.
        
        # We also want to test that invalid unchecked access might throw BoundsError or similar if fully unsafe,
        # OR just return something if bounds checks are also disabled (but we only disabled length==0 check).
        # Bounds checks are @inbounds, so they might segfault or return garbage.
        # We should NOT run unsafe code that segfaults in test suite usually.
        # But we can test that passing unchecked=true WORKS for valid entities.
        
        e2 = new_entity!(world, (Health(20),))
        (h3,) = get_components(world, e2, (Health,); unchecked=true)
        @test h3.value == 20
    end

    @testset "set_components! unchecked" begin
        e = new_entity!(world, (Health(10),))
        set_components!(world, e, (Health(50),); unchecked=true)
        (h,) = get_components(world, e, (Health,))
        @test h.value == 50
    end

    @testset "Internal storage length check skip" begin
        # To test skipping length check, we need a case where length check WOULD fail.
        # Accessing a component that doesn't exist on the entity?
        # get_components(world, e, (Position,)) where e has no Position.
        # Checked: throws "entity has no Position component" (from _get_component length check).
        # Unchecked: assumes it exists.
        # Accessing empty column might just be out of bounds if length is 0?
        # If length is 0, col[row] is out of bounds.
        # But Vector with length 0 accessed at index > 0 is BoundsError.
        # However, we only skip the specific `if length(col) == 0` check.
        # If we access it, @inbounds col[row] might throw if julia bounds checks are on, or segfault.
        # So we can't easily test "success" of failure without potential crash.
        # But we can verify signature works.
    end

    @testset "copy_entity! unchecked" begin
        e = new_entity!(world, (Health(10),))
        e_copy = copy_entity!(world, e; unchecked=true)
        @test is_alive(world, e_copy)
        (h,) = get_components(world, e_copy, (Health,))
        @test h.value == 10
    end

    @testset "remove_entity! unchecked" begin
        e = new_entity!(world, (Health(10),))
        remove_entity!(world, e; unchecked=true)
        @test !is_alive(world, e)
    end

    @testset "has_components unchecked" begin
        e = new_entity!(world, (Health(10),))
        @test has_components(world, e, (Health,); unchecked=true)
        @test !has_components(world, e, (Position,); unchecked=true)
    end

    @testset "add/remove/exchange unchecked" begin
        e = new_entity!(world, (Health(10),))
        add_components!(world, e, (Position(1.0, 2.0),); unchecked=true)
        @test has_components(world, e, (Position,))
        
        remove_components!(world, e, (Health,); unchecked=true)
        @test !has_components(world, e, (Health,))
        
        exchange_components!(world, e, add=(Health(30),), remove=(Position,); unchecked=true)
        @test has_components(world, e, (Health,))
        @test !has_components(world, e, (Position,))
    end

    @testset "Relations unchecked" begin
        e2 = new_entity!(world, ())
        e1 = new_entity!(world, (Relation(),); relations=(Relation => zero_entity,))
        set_relations!(world, e1, (Relation => e2,); unchecked=true)
        
        (rels,) = get_relations(world, e1, (Relation,); unchecked=true)
        @test rels == e2
    end
end
