# Batch operations

In an [archetype-based](@ref Architecture) ECS, creation and removal of entities or components are relatively costly operations.
For these operations, Ark provides batched versions.
This allows to create or manipulate a large number of entities much faster than one by one.
All batch methods come in two flavors. A "normal" one, and one that runs a callback function on the affected entities.

## Creating entities

Often, multiple entities with the same set of components are created at the same time.
Batch entity creation is therefore probably the most frequently used batch operation.
There are different ways to create entities in batches:

From **default component values** using [new_entities!](@ref). Here, we create 100 entities, all with the same `Position` and `Velocity`:

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
    struct Health
        value::Float64
    end
    struct ChildOf end

    world = World(Position, Velocity, Health, Relation{ChildOf})
    entity = new_entity!(world, ())
    parent = new_entity!(world, ())
    parent2 = new_entity!(world, ())
end
```

```jldoctest; output = false
new_entities!(world, 100, (
    Position(100, 100),
    Velocity(0, 0),
))

# output

```

This may be sufficient in some use cases, but most often we will use a second approach:

From **component types** with subsequent manual initialization using [new_entities!](@ref) with a tuple of types:

```jldoctest; output = false
new_entities!(world, 100, (Position, Velocity)) do (entities, positions, velocities)
    for i in eachindex(entities)
        positions[i] = Position(i, i)
        velocities[i] = Velocity(0, 0)
    end
end

# output

```

Note that the tuple elements of the callback argument are entity and component columns
that need to be iterated to access individual items.
See also the chapter on [Queries](@ref), which use a similar nested loop structure.

Note that with the second approach, all components of all entities should be set as they are otherwise uninitialized.
Therefore, the callback is mandatory here, while it is optional for batch creation from default values.

## Removing entities

Similar to entity creation, entities can also be removed in batches with [remove_entities!](@ref).
It takes a [Filter](@ref) instead of a single entity as argument:

```jldoctest; output = false
filter = Filter(world, (Position, Velocity))
remove_entities!(world, filter)

# output

```

If something needs to be done with the entities to be removed, a callback can be used,
which takes an [Entities column](@ref Ark.Entities) as an argument:

```jldoctest; output = false
filter = Filter(world, (Position, Velocity))
remove_entities!(world, filter) do entities
    # do something with the entities...
end

# output

```

## Adding and removing components

The functions [add_components!](@ref), [remove_components!](@ref) and [exchange_components!](@ref) also come with batch versions.

Similarly to batch entity creation, components to be added can be given either in the form of default values, or as types.
In the case of default values, usage of the callback is optional, while it is mandatory for initialization with the types version.

Here, we add a default `Velocity` component to all entities with `Position`, using [add_components!](@ref):

```jldoctest; output = false
filter = Filter(world, (Position,))
add_components!(world, filter, (Velocity(0, 0),))

# output

```

Adding components via types, with individual initialization:

```jldoctest; output = false
filter = Filter(world, (Position,))
add_components!(world, filter, (Velocity,)) do (entities, velocities)
    for i in eachindex(entities, velocities)
        velocities[i] = Velocity(randn(), randn())
    end
end

# output

```

Note that the tuple elements of the callback argument are entity and component columns
that need to be iterated to access individual items.
See also the chapter on [Queries](@ref), which use a similar nested loop structure.

Removing components works in a similar way, with [remove_components!](@ref):

```jldoctest; output = false
filter = Filter(world, (Velocity,))
remove_components!(world, filter, (Velocity,))

# output

```

Note that the optional callback has only an [Entities column](@ref Ark.Entities) as argument:

```jldoctest; output = false
filter = Filter(world, (Velocity,))
remove_components!(world, filter, (Velocity,)) do entities
    # do something with the entities...
end

# output

```

Finally, exchanging components with [exchange_components!](@ref) follows the same pattern as adding components:

```jldoctest; output = false
filter = Filter(world, (Velocity,))
exchange_components!(world, filter;
    add=(Health(100),),
    remove=(Velocity,),
)

# output

```

Note that, again, when adding components as types, the callback is mandatory.
Also note that only the added components are part of the callback's argument tuple,
while the removed components are not.

```jldoctest; output = false
filter = Filter(world, (Velocity,))
exchange_components!(world, filter;
    add=(Health,),
    remove=(Velocity,),
) do (entities, healths)
    for i in eachindex(entities, healths)
        healths[i] = Health(i * 2)
    end
end

# output

```

## Setting relationships

As with other operations, relation targets can be set in batches using [set_relations!](@ref) combined with a [Filter](@ref):

```jldoctest; output=false
filter = Filter(world, (ChildOf => parent,))
set_relations!(world, filter, (ChildOf => parent2,))

# output

```

If necessary, the affected entities can be processed using a callback function:

```jldoctest; output=false
filter = Filter(world, (ChildOf => parent,))
set_relations!(world, filter, (ChildOf => parent2,)) do entities
    # do something with the entities...
end

# output

```
