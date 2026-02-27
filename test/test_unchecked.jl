
@testset "macro expansion @unchecked" begin
    e = @macroexpand @unchecked (h2,) = get_components(world, e, (Health,))
    @test e == :((h2,) = get_components(world, e, (Health,); _unchecked=true))

    e = @macroexpand @unchecked begin
        for e in entities
            e_copy = copy_entity!(world, e)
            (h,) = get_components(world, e_copy, (Health,))

            e_copy_2 = Ark.copy_entity!(world, e; add=(Position(1.0, 2.0),))
            h, p = Ark.get_components(world, e_copy_2, (Health, Position))

            e_copy_2 = Mod.copy_entity!(world, e; add=(Position(1.0, 2.0),))
            h, p = Mod.get_components(world, e_copy_2, (Health, Position))
        end
    end

    @test Base.remove_linenums!(e) == Base.remove_linenums!(
        quote
            for e in entities
                e_copy = copy_entity!(world, e; _unchecked=true)
                (h,) = get_components(world, e_copy, (Health,); _unchecked=true)
                e_copy_2 = Ark.copy_entity!(world, e; add=(Position(1.0, 2.0),), _unchecked=true)
                (h, p) = Ark.get_components(world, e_copy_2, (Health, Position); _unchecked=true)
                e_copy_2 = Mod.copy_entity!(world, e; add=(Position(1.0, 2.0),))
                (h, p) = Mod.get_components(world, e_copy_2, (Health, Position))
            end
        end,
    )

    e = @macroexpand @unchecked get_components(world, e, (Health,), get_components(world, e, (Health,)))
    @test e ==
          :(get_components(world, e, (Health,), get_components(world, e, (Health,); _unchecked=true); _unchecked=true))
end

@testset "get_components unchecked" begin
    world = World(Health, Position, ChildOf)

    e = new_entity!(world, (Health(10),))

    # Normal access
    (h,) = get_components(world, e, (Health,))
    @test h.health == 10

    # Unchecked access
    @unchecked (h2,) = get_components(world, e, (Health,))
    @test h2.health == 10

    # Remove entity to make it dead
    remove_entity!(world, e)
    @test !is_alive(world, e)

    # Checked access throws
    @test_throws ArgumentError get_components(world, e, (Health,))
end

@testset "set_components! unchecked" begin
    world = World(Health, Position, ChildOf)

    e = new_entity!(world, (Health(10),))
    @unchecked set_components!(world, e, (Health(50),))
    (h,) = get_components(world, e, (Health,))
    @test h.health == 50
end

@testset "copy_entity! unchecked" begin
    world = World(Health, Position, ChildOf)

    e = new_entity!(world, (Health(10),))
    @unchecked begin
        e_copy = copy_entity!(world, e)
        @test is_alive(world, e_copy)
        (h,) = get_components(world, e_copy, (Health,))
        @test h.health == 10

        e_copy_2 = copy_entity!(world, e; add=(Position(1.0, 2.0),))
        @test is_alive(world, e_copy_2)
        h, p = get_components(world, e_copy_2, (Health, Position))
        @test h.health == 10
        @test p.x == 1.0 && p.y == 2.0
    end
end

@testset "remove_entity! unchecked" begin
    world = World(Health, Position, ChildOf)

    @unchecked begin
        e = Ark.new_entity!(world, (Health(10),))
        remove_entity!(world, e)
        @test !is_alive(world, e)
    end
end

@testset "has_components unchecked" begin
    world = World(Health, Position, ChildOf)

    @unchecked begin
        e = new_entity!(world, (Health(10),))
        @test has_components(world, e, (Health,))
        @test !has_components(world, e, (Position,))
    end
end

@testset "add/remove/exchange unchecked" begin
    world = World(Health, Position, ChildOf)

    @unchecked begin
        e = new_entity!(world, (Health(10),))
        add_components!(world, e, (Position(1.0, 2.0),))
        @test has_components(world, e, (Position,))

        remove_components!(world, e, (Health,))
        @test !has_components(world, e, (Health,))

        exchange_components!(world, e, add=(Health(30),), remove=(Position,))
        @test has_components(world, e, (Health,))
        @test !has_components(world, e, (Position,))
    end
end

@testset "Relations unchecked" begin
    world = World(Health, Position, ChildOf)

    @unchecked begin
        e2 = new_entity!(world, ())
        e1 = new_entity!(world, (ChildOf(),); relations=(ChildOf => zero_entity,))
        set_relations!(world, e1, (ChildOf => e2,))

        (rels,) = get_relations(world, e1, (ChildOf,))
        @test rels == e2
    end
end
