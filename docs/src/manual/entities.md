# Entities

[Entities](@ref entities-api) are the "game objects" or "model entities" in applications that use Ark.
In effect, an entity is just an ID that can be associated with [Components](@ref),
which contain the entity's properties or state variables.

## [Creating entities](@id creating-entities)

An entity can only exist in a [`World`](@ref), and thus can only be created through a World.

```@meta
DocTestSetup = quote
    using Ark

    struct Position
        x::Float64
        y::Float64
    end
    struct Velocity
        dx::Float64
        dy::Float64
    end

    world = World(Position, Velocity)
    entity = new_entity!(world, ())
end
```

Here, we use [`new_entity!`](@ref) to create an entity with a `Position` and a `Velocity` components.
Note that component values are passed as a tuple!

```jldoctest; output = false
entity = new_entity!(world, (
    Position(100, 100),
    Velocity(0, 0),
))

# output

Entity(3, 0)
```

Components can be added to and removed from the entity later. This is described in the [next chapter](@ref Components).

Often, multiple entities with the same set of components are created at the same time.
For that sake, Ark provides batch entity creation, which is much faster than creating entities one by one.
See chapter [Batch operations](@ref) for details.

## Removing entities

Removing an entity from the World is as simple as this, using [`remove_entity!`](@ref):

```jldoctest; output = false
remove_entity!(world, entity)

# output

```

For removing many entities in batches, see chapter [Batch operations](@ref).

## Alive status

Entities can be safely stored, e.g. in the [Components](@ref) of other entities to represent relationships. However, as they may have been removed from the world elsewhere,
it may be necessary to check whether an entity is still alive with [`is_alive`](@ref):

```@meta
DocTestSetup = quote
    using Ark
    world = World()
    entity = new_entity!(world, ())
end
```

```jldoctest entities; output = false
if is_alive(world, entity)
    # ...
end

# output

```

## Zero entity

There is a reserved [`zero_entity`](@ref) that can be used as a placeholder for "no entity".
The zero entity is never alive.
The function [`is_zero`](@ref) can be used to determine whether an entity is the zero entity:

```jldoctest entities; output = false
if is_zero(entity)
    # ...
end

# output

```
