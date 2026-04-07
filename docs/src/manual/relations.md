# Entity relationships

In a basic ECS, relations between entities, like hierarchies, can be represented
by storing entities in components.
E.g., we could have a child component like this:

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
    struct ChildOf <: Relationship end
    struct RenderLayer <: Relationship end

    world = World(Position, Velocity, ChildOf, RenderLayer)
    entity = new_entity!(world, ())
    parent = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    layer1 = new_entity!(world, ())
end
```

```jldoctest; output=false
struct ChildOf
    parent::Entity
end

# output

```

Or, alternatively, a parent component with many children:

```jldoctest; output=false
struct Parent
    children::Vector{Entity}
end

# output

```

This may be sufficient for many use cases.
However, we are not able to leverage the power of queries to e.g. get all children of a particular parent in an efficient way.

To make entity relations even more useful and efficient, Ark.jl supports them as a first class feature.
Relations are added to and removed from entities just like components,
and hence can be queried like components, with the usual efficiency.
This is achieved by creating separate sub-tables inside [archetypes](@ref Architecture)
for relations with different target entities.

## Relation components

To use entity relations, create components that are sub-types of the abstract marker type [Relationship](@ref):

```jldoctest; output=false
struct ChildOf <: Relationship
end

# output

```

That's all to make a component be treated as an entity relationship by Ark.
Relation components can contain variables/fields like usual components, but in many cases they will just be empty structs.

## Creating relations

All functions that create or add components take a keyword argument `relations` that allows to specify target entities for relationship components using tuples of `Type => Entity` pairs.

### On new entities

To create an entity with relations, add a relationship component and specify it's target entity using [new_entity!](@ref):

```jldoctest; output=false
entity = new_entity!(world, 
                     (Position(0, 0), ChildOf());
                     relations=(ChildOf => parent,))

# output

Entity(6, 0)
```

This works in the same way for batch entity creation with [new_entities!](@ref).

Multiple relationships can be used in a similar way:

```jldoctest; output=false
entity = new_entity!(world, 
                     (Position(0, 0), ChildOf(), RenderLayer());
                     relations=(ChildOf => parent, RenderLayer => layer1))

# output

Entity(6, 0)
```

Note that, when creating entities with relationship components, targets for all relations must be specified.

### When adding components

Relation target must also be given when adding relation components to an entity with [add_components!](@ref):

```jldoctest; output=false
add_components!(world, entity, (ChildOf(),); relations=(ChildOf => parent,))

# output

```

The same applies for [exchange_components!](@ref),

## Get and set relations

We can also change the target entity of an already assigned relation component.
This is done via [set_relations!](@ref) or by indexing with an entity handle:

```jldoctest; output=false
entity = new_entity!(world, 
                     (Position(0, 0), ChildOf());
                     relations=(ChildOf => parent,))

set_relations!(world, entity, (ChildOf => parent2,))
# or via handle
we = world[entity]
we.rel[ChildOf] = parent2

# output

```

This also works for changing the targets of multiple relations in one function call.

Target entities can be retrieved with [get_relations](@ref) or by indexing:

```jldoctest; output=false
entity = new_entity!(world, 
                     (Position(0, 0), ChildOf());
                     relations=(ChildOf => parent,))

parent_entity, = get_relations(world, entity, (ChildOf,))
# or via handle
we = world[entity]
parent_entity = we.rel[ChildOf]

# output

(Entity(3, 0),)
```

Note that [get_relations](@ref) always returns a tuple of entities, while indexing `we.rel[RelationComponent]` returns the single target entity directly.

As with other operations, relation targets can be set in batches. See chapter [Batch operations](@ref) for details.

## Querying relations

Queries support filtering for relation targets using the keyword argument `relations` in the same way as already shown:

```jldoctest; output=false
for (entities, children) in Query(world, (ChildOf,); relations=(ChildOf => parent,))
    # ...
end

# output

```

In many use cases, relation components don't contain any data.
Here, component values are not required in the query iteration.
It is thus sufficient to have the relation component in the query's `with`:

```jldoctest; output=false
for (entities,) in Query(world, (); with=(ChildOf,), relations=(ChildOf => parent,))
    # ...
end

# output

```

Note that when querying for relations without specifying target entities,
entities for all targets will be included in the iteration.
Similarly, if the targets for some of multiple relations of an entity are not specified,
these are treated as wildcards.

## Dead target entities

Entities that are the target of any relationships can be removed from the world like any other entity.
When this happens, all entities that have this target in a relation get assigned to the zero entity as target.
The respective [archetype](@ref Architecture) sub-table is de-activated and marked for potential re-use for another target entity.

## Limitations

Unlike [Flecs](https://flecs.dev), the ECS that pioneered entity relationships,
Ark is limited to supporting only "exclusive" relationships.
This means that any relationship (i.e. relationship type/component) can only have a single target entity.
An entity can, however, have multiple different relationship types at the same time.

The limitation to a single target is mainly a performance consideration.
Firstly, the possibility for multiple targets would require a different,
slower approach for component mapping in archetypes.
Secondly, usage of multiple targets would easily lead to archetype fragmentation,
as a separate archetype sub-table would be created for each unique combination of targets.

Entity relationships in Ark are still a very powerful feature,
while discouraging use cases where they could easily lead to poor performance.
For more details on when entity relationships are the most effective and efficient,
see the next section.

## When to use, and when not

When using Ark's entity relations, an archetype sub-table is created for each target entity of a relation.
Thus, entity relations are not efficient if the number of target entities is high (tens of thousands),
while only a low number of entities has a relation to each particular target (less than a few dozens).
Particularly in the extreme case of 1:1 relations, storing entities in components
as explained in the introduction of this chapter is more efficient.

However, with a moderate number of relation targets, particularly with many entities per target,
entity relations are very efficient.

Beyond use cases where the relation target is a "physical" entity that appears
in a simulation or game, targets can also be more abstract, like categories.
Examples:

 - Different tree species in a forest model.
 - Behavioral states in a finite state machine.
 - The opposing factions in a strategy game.
 - Render layers in a game or other graphical application.

This concept is particularly useful for things that would best be expressed by components,
but the possible components (or categories) are only known at runtime.
Thus, it is not possible to create ordinary components for them.
However, these categories can be represented by entities, which are used as relation targets.
