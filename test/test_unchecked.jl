
@testset "get_components unchecked" begin

    world = World(Health, Position, Relation)

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

    e2 = new_entity!(world, (Health(20),))
    (h3,) = get_components(world, e2, (Health,); unchecked=true)
    @test h3.value == 20
end

@testset "set_components! unchecked" begin
    world = World(Health, Position, Relation)

    e = new_entity!(world, (Health(10),))
    set_components!(world, e, (Health(50),); unchecked=true)
    (h,) = get_components(world, e, (Health,))
    @test h.value == 50
end

@testset "copy_entity! unchecked" begin
    world = World(Health, Position, Relation)

    e = new_entity!(world, (Health(10),))
    e_copy = copy_entity!(world, e; unchecked=true)
    @test is_alive(world, e_copy)
    (h,) = get_components(world, e_copy, (Health,))
    @test h.value == 10
end

@testset "remove_entity! unchecked" begin
    world = World(Health, Position, Relation)

    e = new_entity!(world, (Health(10),))
    remove_entity!(world, e; unchecked=true)
    @test !is_alive(world, e)
end

@testset "has_components unchecked" begin
    world = World(Health, Position, Relation)

    e = new_entity!(world, (Health(10),))
    @test has_components(world, e, (Health,); unchecked=true)
    @test !has_components(world, e, (Position,); unchecked=true)
end

@testset "add/remove/exchange unchecked" begin
    world = World(Health, Position, Relation)

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
    world = World(Health, Position, Relation)

    e2 = new_entity!(world, ())
    e1 = new_entity!(world, (Relation(),); relations=(Relation => zero_entity,))
    set_relations!(world, e1, (Relation => e2,); unchecked=true)
    
    (rels,) = get_relations(world, e1, (Relation,); unchecked=true)
    @test rels == e2
end
