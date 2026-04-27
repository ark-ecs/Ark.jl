
@testset "Indexing API" begin
    world = World(Position, Velocity, ChildOf, ChildOf2)

    e1 = new_entity!(world, (Position(1.0, 2.0), Velocity(0.1, 0.2), ChildOf());
        relations=(ChildOf => zero_entity,))
    e2 = new_entity!(world, (Position(10.0, 20.0), ChildOf());
        relations=(ChildOf => e1,))
    e3 = new_entity!(world, (Position(0.0, 0.0), ChildOf(), ChildOf2()),
        relations=(ChildOf => e1, ChildOf2 => e2))
    we1 = world[e1]
    we2 = world[e2]
    we3 = world[e3]

    @testset "Components" begin
        # getting
        @test we1[Position] == Position(1.0, 2.0)
        @test we1[(Position, Velocity)] == (Position(1.0, 2.0), Velocity(0.1, 0.2))

        # has components
        @test Position in we1
        @test Velocity in we1
        @test (Position, Velocity) in we1
        @test !(Velocity in we2)

        # setting
        we1[Position] = Position(3.0, 4.0)
        @test we1[Position] == Position(3.0, 4.0)

        we1[(Position, Velocity)] = (Position(5.0, 6.0), Velocity(0.5, 0.6))
        @test we1[Position] == Position(5.0, 6.0)
        @test we1[Velocity] == Velocity(0.5, 0.6)

        # add / remove
        remove_components!(we1, (Velocity,))
        @test !(Velocity in we1)
        add_components!(we1, (Velocity(1.0, 1.0),))
        @test Velocity in we1
        @test we1[Velocity] == Velocity(1.0, 1.0)
    end

    @testset "Relations" begin
        @test we1.rel[ChildOf] == zero_entity
        we1.rel[ChildOf] = e2
        @test we1.rel[ChildOf] == e2

        @test we2.rel[ChildOf] == e1
        we2.rel[ChildOf] = e2
        @test we2.rel[ChildOf] == e2

        e4 = new_entity!(world, (Position(1.0, 1.0),))
        e5 = new_entity!(world, (Position(2.0, 2.0),))

        we3.rel[(ChildOf, ChildOf2)] = (e1, e2)

        @test we3.rel[ChildOf] == e1
        @test we3.rel[ChildOf2] == e2
        we3.rel[(ChildOf, ChildOf2)] = (e4, e5)
        @test we3.rel[(ChildOf, ChildOf2)] == (e4, e5)
    end

    @testset "Unchecked" begin
        @unchecked begin
            @test we1[Position] == Position(5.0, 6.0)
            @test Base.getindex(we1, Position) == Position(5.0, 6.0)
            we1[Position] = Position(7.0, 8.0)
            @test we1[Position] == Position(7.0, 8.0)
            @test Position in we1

            we1[(Position, Velocity)] = (Position(9.0, 10.0), Velocity(1.1, 1.2))
            @test we1[(Position, Velocity)] == (Position(9.0, 10.0), Velocity(1.1, 1.2))
            @test (Position, Velocity) in we1

            remove_components!(we1, (Velocity,))
            @test !(Velocity in we1)
            add_components!(we1, (Velocity(2.0, 2.0),))
            @test Velocity in we1

            we1.rel[ChildOf] = e2
            @test we1.rel[ChildOf] == e2

            we3.rel[(ChildOf, ChildOf2)] = (e2, e1)
            @test we3.rel[(ChildOf, ChildOf2)] == (e2, e1)
        end

        expr = @macroexpand @unchecked begin
            we1[Position] == Position(5.0, 6.0)
            Base.getindex(we1, Position) == Position(5.0, 6.0)
            we1[Position] = Position(7.0, 8.0)
            we1[Position] == Position(7.0, 8.0)
            Position in we1
            we1[(Position, Velocity)] = (Position(9.0, 10.0), Velocity(1.1, 1.2))
            we1[(Position, Velocity)] == (Position(9.0, 10.0), Velocity(1.1, 1.2))
            (Position, Velocity) in we1
            remove_components!(we1, (Velocity,))
            !(Velocity in we1)
            add_components!(we1, (Velocity(2.0, 2.0),))
            Velocity in we1
            we1.rel[ChildOf] = e2
            we1.rel[ChildOf] == e2
            we3.rel[(ChildOf, ChildOf2)] = (e2, e1)
            we3.rel[(ChildOf, ChildOf2)] == (e2, e1)
        end

        @test Base.remove_linenums!(expr) == Base.remove_linenums!(
            quote
                Ark._unchecked_getindex(we1, Position) == Position(5.0, 6.0)
                Ark._unchecked_getindex(we1, Position) == Position(5.0, 6.0)
                Ark._unchecked_setindex!(we1, Position(7.0, 8.0), Position)
                Ark._unchecked_getindex(we1, Position) == Position(7.0, 8.0)
                Ark._unchecked_in(Position, we1)
                Ark._unchecked_setindex!(we1, (Position(9.0, 10.0), Velocity(1.1, 1.2)), (Position, Velocity))
                Ark._unchecked_getindex(we1, (Position, Velocity)) == (Position(9.0, 10.0), Velocity(1.1, 1.2))
                Ark._unchecked_in((Position, Velocity), we1)
                remove_components!(we1, (Velocity,); _unchecked=true)
                !(Ark._unchecked_in(Velocity, we1))
                add_components!(we1, (Velocity(2.0, 2.0),); _unchecked=true)
                Ark._unchecked_in(Velocity, we1)
                Ark._unchecked_setindex!(we1.rel, e2, ChildOf)
                Ark._unchecked_getindex(we1.rel, ChildOf) == e2
                Ark._unchecked_setindex!(we3.rel, (e2, e1), (ChildOf, ChildOf2))
                Ark._unchecked_getindex(we3.rel, (ChildOf, ChildOf2)) == (e2, e1)
            end,
        )

        @test Ark._unchecked_getindex([1], 1) == 1
        @test Ark._unchecked_setindex!([1], 2, 1) == [2]
        @test Ark._unchecked_in(1, [1]) == true
    end
end
