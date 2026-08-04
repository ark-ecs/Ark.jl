# Architecture

This chapter describes the principles of Ark's architecture,
which may be useful to understand what is actually going on,
and to understand performance trade-offs.

## [Archetypes](@id archetypes)

Ark uses an archetype-based architecture (therefore its name).

An archetype represents a unique combination of components.
Each archetype stores the data for all entities that share exactly that combination.
You can think of an archetype as a table, where rows correspond to entities
and columns represent components. The first column always contains the entity identifiers themselves.

The ASCII graph below illustrates the approach.
The first column shows the entity index, which is used for [World component access](@ref component-access).
The second columns shows archetypes. In this example, the first archetype contains all entities with
components A, B and C. The second archetype contains all entities with A and B, and so on.
The first column of each archetype contains the entity identifier for each row.

```text
 Entities   Archetypes   Bitmasks   Component index
                                    .-----------.
                                    | A | B | C |
   E         E Comps                '-----------'
  |0|       |2|A|B|C|    111... <-----|<--|<--|
  |1|---.   |8|A|B|C|                 |   |   |
  |2|   '-->|1|A|B|C|                 |   |   |
  |3|       |3|A|B|C|                 |   |   |
  |4|                                 |   |   |
  |6|   .-->|7|A|B|      110... <-----'<--|   |
  |7|---'   |6|A|B|                       |   |
  |8|       |4|A|B|                       |   |
  |9|---.                                 |   |
  |.|   |   |5|B|C|      011... <---------'<--'
  |.|   '-->|9|B|C|
  |.|
  |.| <===> [Entity pool]
```
*Illustration of Ark's archetype-based architecture.*

Each archetype has a bit mask (3rd column) that encodes its components and serves for fast checks in queries.
Finally, the last column shows the component index. See the next section for details.

## [Queries](@id architecture-queries)

[Queries](@ref) serve for iterating and manipulating all entities that have certain components.
With the architecture presented here, queries are particularly fast for several reasons:

- Queries make a pre-selection of relevant archetypes using the component index, based on the most "rare" component.
- Queries do a fast bit mask check per archetype in the pre-selection.
- Once an archetype is checked as matching, entities in that archetype can be iterated linearly without further checks.
- Components are stored in array-like columns per archetype, so only the necessary component data needs to be loaded into the CPU cache.

In worlds with a large number of archetypes, query performance can be further improved by [filter caching](@ref filter-caching).

## [World component access](@id component-access)

To retrieve components for a specific entity outside query iteration ([get_components](@ref get_components(::World, ::Entity, ::Tuple))),
the World maintains a list indexed by entity ID (the entity index at the very left in the graph above).
Each entry in this list points to the entity's archetype and the position within the archetype's table.

This setup enables fast random access to component data, though slightly slower than query-based iteration due to the additional indirection.

Note that the entity index also contains entities that are currently not alive, because they were removed from the World.
These entities are recycled when new entities are requested from the world.
Therefore, besides the ID shown in the illustration, each entity also has a generation variable.
It is incremented on each "reincarnation",
which allows to distinguish recycled from dead entities, as well as from previous or later "incarnations".

## [Entity relationships](@id architecture-relationships)

Earlier, archetypes were described as flat tables.
However, with Ark’s [Entity relationships](@ref "Entity relationships") feature,
archetypes can contain multiple sub-tables, each corresponding to a unique combination of relation targets.

As an example, we have components `A`, `B` and `R`, where `R` is a relation.
Further, we have two parent entities `E1` and `E2`.
When you create some entities with components `A B R(E1)` and `A B R(E2)`,
i.e. with relation targets `E1` and `E2`, the following archetype is created:

```text
  Archetype [ A B R ]
    |
    |--- E1   E Comps
    |        |3|A|B|R|
    |        |6|A|B|R|
    |        |7|A|B|R|
    |
    '--- E2   E Comps
             |4|A|B|R|
             |5|A|B|R|
```
*Relationship tables of an archetype*

When querying without specifying a target, the archetype's tables are simply iterated if the archetype matches the filter.
When querying with a relation target (and the archetype matches), the table for the target entity is looked up in a standard `Dict`.

If the archetype contains multiple relation components, a `Dict` lookup is used to get all tables matching the target that is specified first. These tables are simply iterated if no further target is specified. If more than one target is specified, the selected tables are checked for these further targets and skipped if they don't match.

## Archetype removal

Normal archetype tables without a relation are never removed, because they are not considered temporary.
For relation archetypes, however, things are different.
Once a target entity dies, it will never appear again (actually it could, after dying another 4,294,967,294 times).

In Ark, empty tables with a dead relationship target are recycled.
They are deactivated, but their allocated memory for entities and components is retained.
When a table in the same archetype, but for another target entity is requested, a recycled table is reused if available.
To be able to efficiently detect whether a table can be removed,
a bitset is used to keep track of entities that are the target of a relationship.

## Performance implications

Archetypes are primarily designed to maximize iteration speed by grouping entities with identical
component sets into tightly packed memory layouts.
This structure enables blazing-fast traversal and component access during queries.

However, this optimization comes with a trade-off: Adding or removing components from an entity,
as well as setting relationship targets, requires relocating it to a different archetype,
essentially moving all of its component data.
This operation typically costs ≈20ns per involved component, plus some baseline cost.

To reduce the number of archetype changes, it is recommended to add/remove/exchange multiple components at the same time
rather than one after the other. Further, operations can be [batched](@ref "Batch operations") to manipulate many entities in a single command.

For detailed benchmarks and performance metrics, refer to the [Benchmarks](@ref) chapter.
