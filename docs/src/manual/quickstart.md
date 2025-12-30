# Quickstart

This page shows how to install Ark.jl, and gives a minimal usage example.

Finally, it points into possible directions to continue.

## Installation

Run this to add Ark.jl to a Julia project:

```julia
using Pkg
Pkg.add("Ark")
```

## Example

Here is the classical Position/Velocity example that every ECS shows in the docs.

Read the next chapters and view the [API docs](https://ark-ecs.github.io/Ark.jl/stable/api)
and [demos](https://github.com/ark-ecs/Ark.jl/tree/main/demos) for more details.

```jldoctest; output = false
using Ark

"""Position component"""
struct Position
    x::Float64
    y::Float64
end

"""Velocity component"""
struct Velocity
    dx::Float64
    dy::Float64
end

# Create a world with the required components
world = World(Position, Velocity)

for i in 1:1000
    # Create an entity with components
    entity = new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
end

# Time loop
for i in 1:10
    # Iterate a query (archetypes)
    for (entities, positions, velocities) in Query(world, (Position, Velocity))
        # Iterate entities in the current archetype
        @inbounds for i in eachindex(entities)
            # Get components of the current entity
            pos = positions[i]
            vel = velocities[i]
            # Update an (immutable) component
            positions[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
end

# output

```

## What's next?

If you ask **"What is ECS?"**, take a look at the great [**ECS FAQ**](https://github.com/SanderMertens/ecs-faq) by Sander Mertens, the author of the [Flecs](http://flecs.dev) ECS.

To learn how to use Ark.jl, read the following chapters,
browse the [API documentation](https://ark-ecs.github.io/Ark.jl/stable/api.html),
or take a look at the [GitHub repository](https://github.com/ark-ecs/Ark.jl).
