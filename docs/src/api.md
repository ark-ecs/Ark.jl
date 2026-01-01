# API

Ark's public API.

```@contents
Pages = ["api.md"]
Depth = 2:2
```

## [World](@id world-api)

The [World](@ref "The World") is the central data storage for [Entities](@ref entities-api), [Components](@ref components-api)
and [Resources](@ref resources-api).

```@docs
World
World(::Type...)
reset!
is_locked
Relationship
```

## [Entities](@id entities-api)

[Entities](@ref) are the "game objects" or "model entities".
An entity if just an ID with a generation, but [Components](@ref components-api)
can be attached to an entity.

```@docs
Entity
zero_entity
new_entity!
new_entities!
remove_entity!
remove_entities!
copy_entity!
is_alive
is_zero
```

## [Components](@id components-api)

[Components](@ref) contain the data associated with [Entities](@ref entities-api).

```@docs
get_components
has_components
set_components!
add_components!
remove_components!
exchange_components!
get_relations
set_relations!
```

## [Storages](@id storage-api)

[Storages](@ref component-storages) define the data structures for the containers of
[Components](@ref). The default ones are Vector and [StructArray](@ref),
but new ones can be defined implementing the [Storage Interface](@ref new-component-storages).

```@docs
Storage
StructArray
```

## [Queries and Filters](@id queries-api)

[Queries](@ref) are used to filter and process [Entities](@ref entities-api) with a
certain set of [Components](@ref components-api).

```@docs
Query
Query(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)
Query(::Filter)
close!(::Query)
Filter
Filter(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)
unregister!
count_entities
length
Entities
@unpack
unpack
```

## [Resources](@id resources-api)

[Resources](@ref) are singleton-like data structures that appear only once in a [World](@ref world-api)
and are not associated to an [Entity](@ref entities-api).

```@docs
get_resource
has_resource
add_resource!
set_resource!
remove_resource!
```

## [Event system](@id events-api)

The [event system](@ref "Event system") allows user code to react on structural changes
like entity creation and removal and component addition and removal.
Further, custom events can be defined and emitted.

```@docs
EventType
EventRegistry
EventRegistry()
new_event_type!
Observer
observe!
emit_event!
```

## Index

```@index
Pages = ["api.md"]
```
