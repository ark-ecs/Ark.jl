
@testset "World new_entities! with values" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        Altitude,
    )

    new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    e = new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    remove_entity!(world, e)

    count = 0
    new_entities!(world, 0, (Position(99, 99), Velocity(99, 99))) do (ent, pos_col, vel_col)
        count += length(ent)
    end
    new_entities!(world, 0, (Position(99, 99), Velocity(99, 99)))
    new_entities!(world, 0, ())

    new_entities!(world, 100, (Position(99, 99), Velocity(99, 99))) do (ent, pos_col, vel_col)
        @test length(ent) == 100
        @test length(pos_col) == 100
        @test length(vel_col) == 100
        @test pos_col isa FieldViewable
        @test vel_col isa _StructArrayView
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            @test pos_col[i] == Position(99, 99)
            @test vel_col[i] == Velocity(99, 99)
            pos_col[i] = Position(i + 1, i + 1)
            vel_col[i] = Velocity(i + 1, i + 1)
            count += 1
        end
        @test is_locked(world) == true
    end
    @test count == 100
    @test is_locked(world) == false
    @test length(world._tables[2].entities) == 101
    @test length(world._storages[offset_ID+2].data[2]) == 101
    @test length(world._storages[offset_ID+3].data[2]) == 101

    count = 0
    for (ent, pos_col, vel_col) in Query(world, (Position, Velocity))
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            @test pos_col[i] == Position(i, i)
            count += 1
        end
    end
    @test count == 101

    new_entities!(world, 100, (Position(13, 13), Velocity(13, 13)))
    @test is_locked(world) == false

    count = 0
    for (ent, pos_col, vel_col) in Query(world, (Position, Velocity))
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            if i <= 101
                @test pos_col[i] == Position(i, i)
            else
                @test pos_col[i] == Position(13, 13)
            end
            count += 1
        end
    end
    @test count == 201

    new_entities!(world, 100, ()) do (ent,)
        @test length(ent) == 100
    end
end