
@testset "README example" begin
    # Create a world with the required components
    world = TestWorld(Position, Velocity)

    for i in 1:1000
        # Create an entity with components
        entity = new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
    end

    # Time loop
    for i in 1:10
        # Iterate a query (archetypes)
        for (entities, pos_column, vel_column) in Query(world, (Position, Velocity))
            # Iterate entities in the current archetype
            for i in eachindex(pos_column)
                # Get components of the current entity
                pos = pos_column[i]
                vel = vel_column[i]
                # Update an (immutable) component
                pos_column[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
            end
        end
    end
end
