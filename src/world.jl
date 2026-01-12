
"""
    const zero_entity::Entity

The reserved zero [Entity](@ref) value.
Can be used to represent "no entity"/"nil".
"""
const zero_entity::Entity = _new_entity(1, 0)

const _no_entity::Entity = _new_entity(0, 0)

const _empty_relations::Vector{Pair{Int,Entity}} = Vector{Pair{Int,Entity}}()

struct _WorldPool{M}
    relations::Vector{Pair{Int,Entity}}
    entities::Vector{Entity}
    tables::Vector{UInt32}
    batches::Vector{_BatchTable{M}}
    mask::_MutableMask{M}
end

function _WorldPool{M}() where {M}
    return _WorldPool(
        Vector{Pair{Int,Entity}}(),
        Vector{Entity}(),
        Vector{UInt32}(),
        Vector{_BatchTable{M}}(),
        _MutableMask{M}(),
    )
end

"""
    World{CS<:Tuple,CT<:Tuple,ST<:Tuple,N,M}

The World is the central storage for [entities](@ref Entities),
[components](@ref Components) and [resources](@ref Resources).

See the constructor [World](@ref World(::Union{Type,Pair}...; ::Int, ::Bool)) for details.
"""
mutable struct World{CS<:Tuple,CT<:Tuple,ST<:Tuple,N,M} <: _AbstractWorld
    const _entities::Vector{_EntityIndex}
    const _targets::BitVector
    const _storages::CS
    const _relations::Vector{_ComponentRelations}
    const _archetypes::Vector{_Archetype{M}}
    const _archetypes_hot::Vector{_ArchetypeHot{M}}
    const _relation_archetypes::Vector{UInt32}
    const _tables::Vector{_Table}
    const _index::_ComponentIndex{M}
    const _registry::_ComponentRegistry
    const _entity_pool::_EntityPool
    const _lock::_Lock
    const _graph::_Graph{M}
    const _resources::Dict{DataType,Any}
    const _event_manager::_EventManager{World{CS,CT,ST,N,M},M}
    const _cache::_Cache{M}
    const _pool::_WorldPool{M}
    const _initial_capacity::Int
end

"""
    World(
        comp_types::Type...;
        initial_capacity::Int=128,
        allow_mutable::Bool=false,
    )

Creates a new, empty [World](@ref) for the given component types.

All component types that will be used with the world must be specified.
This allows Ark to use Julia's compile-time method generation to achieve the best performance.

For each component type, an individual [storage mode](@ref component-storages) can be set.
See also [VectorStorage](@ref) and [StructArrayStorage](@ref).

Additional arguments can be used to allow mutable component types (forbidden by default and discouraged)
and an initial capacity for entities in [archetypes](@ref Architecture).

# Arguments

  - `comp_types`: The component types used by the world.
  - `initial_capacity`: Initial capacity for entities in each archetype and in the entity index.
  - `allow_mutable`: Allows mutable components. Use with care, as all mutable objects are heap-allocated in Julia.

# Examples

A World where all components use the default storage mode:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
world = World(
    Position,
    Velocity,
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

A World with individually configured storage modes:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
world = World(
    Position => StructArrayStorage,
    Velocity => StructArrayStorage,
    Health => VectorStorage,
)

# output

World(entities=0, comp_types=(Position, Velocity, Health))
```
"""
function World(comp_types::Union{Type,Pair{<:Type,<:Type}}...; initial_capacity::Int=128, allow_mutable=false)
    types = map(arg -> arg isa Type ? arg : arg.first, comp_types)
    storages = map(arg -> arg isa Type ? VectorStorage : arg.second, comp_types)

    _World_from_types(Val{Tuple{types...}}(), Val{Tuple{storages...}}(), Val(allow_mutable), initial_capacity)
end

"""
    new_entity!(world::World, values::Tuple; relations::Tuple=())::Entity

Creates a new [Entity](@ref) with the given component values. Types are inferred from the values.

# Arguments

  - `world::World`: The `World` instance to use.
  - `values::Tuple`: Component values for the entity.
  - `defaults::Tuple`: A tuple of default values for initialization, like `(Position(0, 0), Velocity(1, 1))`.
  - `relations::Tuple`: Relationship component type => target entity pairs.

# Examples

Create an entity with components:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
entity = new_entity!(world, (Position(0, 0), Velocity(1, 1)))

# output

Entity(5, 0)
```

Create an entity with components and relationships:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
entity = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,))

# output

Entity(5, 0)
```
"""
Base.@constprop :aggressive function new_entity!(
    world::World,
    values::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))

    entity, table_id = _new_entity!(world, Val{typeof(values)}(), values, rel_types, targets)

    has_entity_obs = _has_observers(world._event_manager, OnCreateEntity)
    has_rel_obs = !isempty(relations) && _has_observers(world._event_manager, OnAddRelations)
    if has_entity_obs || has_rel_obs
        table = world._tables[table_id]
        mask = world._archetypes_hot[table.archetype].mask
        if has_entity_obs
            _fire_create_entity(world._event_manager, entity, mask)
        end
        if has_rel_obs
            _fire_create_entity_relations(world._event_manager, entity, mask)
        end
    end
    return entity
end

"""
    copy_entity!(
        world::World,
        entity::Entity;
        add::Tuple=(),
        remove::Tuple=(),
        relations::Tuple=(),
        mode=:copy,
    )

Copies an [Entity](@ref), optionally adding and/or removing components.

Mutable and non-isbits components are shallow copied by default. This can be changed with the `mode` argument.

# Arguments

  - `world`: The `World` instance to query.
  - `entity::Entity`: The entity to copy.
  - `add::Tuple`: Components to add, like `with=(Health(0),)`.
  - `remove::Tuple`: Component types to remove, like `(Position,Velocity)`.
  - `relations::Tuple`: Relationship component type => target entity pairs.
  - `mode::Tuple`: Copy mode for mutable and non-isbits components. Modes are :ref, :copy, :deepcopy.

# Examples

Simple copy of an entity:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
entity1 = copy_entity!(world, entity)

# output

Entity(5, 0)
```

Copy an entity, adding and removing some components in the same operation:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
entity2 = copy_entity!(world, entity;
    add=(Health(100),),
    remove=(Position, Velocity),
)

# output

Entity(5, 0)
```
"""
@inline Base.@constprop :aggressive function copy_entity!(
    world::World, entity::Entity;
    add::Tuple=(), remove::Tuple=(),
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
    mode::Symbol=:copy,
)
    if !is_alive(world, entity)
        throw(ArgumentError("can't copy a dead entity"))
    end
    if isempty(add) && isempty(remove) && isempty(relations)
        return @inline _copy_entity!(world, entity, Val(mode))
    end
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _copy_entity!(
        world,
        entity,
        Val{typeof(add)}(),
        add,
        ntuple(i -> Val(remove[i]), length(remove)),
        rel_types, targets,
        Val(mode),
    )
end

"""
    remove_entity!(world::World, entity::Entity)

Removes an [Entity](@ref) from the [World](@ref).

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
remove_entity!(world, entity)

# output

```
"""
@generated function remove_entity!(world::W, entity::Entity) where {W<:World}
    CS = W.parameters[1]
    inline_jtable = length(CS.parameters) <= 10
    world_has_rel = _has_relations(CS)
    quote
        if !is_alive(world, entity)
            throw(ArgumentError("can't remove a dead entity"))
        end
        _check_locked(world)

        @inbounds index = world._entities[entity._id]
        @inbounds table = world._tables[index.table]
        @inbounds archetype = world._archetypes[table.archetype]

        has_entity_obs = _has_observers(world._event_manager, OnRemoveEntity)
        has_rel_obs = _has_relations(archetype) && _has_observers(world._event_manager, OnRemoveRelations)
        if has_entity_obs || has_rel_obs
            l = _lock(world._lock)
            if has_entity_obs
                _fire_remove_entity(world._event_manager, entity, archetype.node.mask)
            end
            if has_rel_obs
                _fire_remove_entity_relations(world._event_manager, entity, archetype.node.mask)
            end
            _unlock(world._lock, l)
        end

        swapped = _swap_remove!(table.entities._data, index.row)

        # Only operate on storages for components present in this archetype
        for comp in archetype.components
            $(
                inline_jtable ?
                :(@inline _swap_remove_in_column_for_comp!(world, comp, index.table, index.row)) :
                :(_swap_remove_in_column_for_comp!(world, comp, index.table, index.row))
            )
        end

        if swapped
            @inbounds swap_entity = table.entities[index.row]
            @inbounds world._entities[swap_entity._id] = index
        end

        _recycle(world._entity_pool, entity)

        $(world_has_rel ?
          :(
            if world._targets[entity._id]
                _cleanup_archetypes(world, entity)
                world._targets[entity._id] = false
            end
        ) :
          (:(nothing))
        )

        return nothing
    end
end

"""
    get_components(world::World, entity::Entity, comp_types::Tuple)

Get the given components for an [Entity](@ref).
Components are returned as a tuple.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
pos, vel = get_components(world, entity, (Position, Velocity))

# output

(Position(0.0, 0.0), Velocity(0.0, 0.0))
```
"""
@inline Base.@constprop :aggressive function get_components(world::World, entity::Entity, comp_types::Tuple)
    if !is_alive(world, entity)
        throw(ArgumentError("can't get components of a dead entity"))
    end
    return @inline _get_components(world, entity, ntuple(i -> Val(comp_types[i]), length(comp_types)))
end

"""
    has_components(world::World, entity::Entity, comp_types::Tuple)::Bool

Returns whether an [Entity](@ref) has all given components.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
has = has_components(world, entity, (Position, Velocity))

# output

true
```
"""
@inline Base.@constprop :aggressive function has_components(world::World, entity::Entity, comp_types::Tuple)
    if !is_alive(world, entity)
        throw(ArgumentError("can't check components of a dead entity"))
    end
    index = world._entities[entity._id]
    return @inline _has_components(world, index, ntuple(i -> Val(comp_types[i]), length(comp_types)))
end

"""
    set_components!(world::World, entity::Entity, values::Tuple)

Sets the given component values for an [Entity](@ref). Types are inferred from the values.
The entity must already have all these components.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
set_components!(world, entity, (Position(0, 0), Velocity(1, 1)))

# output

```
"""
@inline Base.@constprop :aggressive function set_components!(world::World, entity::Entity, values::Tuple)
    if !is_alive(world, entity)
        throw(ArgumentError("can't set components of a dead entity"))
    end
    return @inline _set_components!(world, entity, Val{typeof(values)}(), values)
end

"""
    get_relations(world::World, entity::Entity, comp_types::Tuple)

Get the relation targets for components of an [Entity](@ref).
Targets are returned as a tuple.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
parent, = get_relations(world, entity, (ChildOf,))

# output

(Entity(2, 0),)
```
"""
@inline Base.@constprop :aggressive function get_relations(world::W, entity::Entity, comp_types::Tuple) where {W<:World}
    if !is_alive(world, entity)
        throw(ArgumentError("can't get relations of a dead entity"))
    end
    return @inline _get_relations(world, entity, ntuple(i -> Val(comp_types[i]), length(comp_types)))
end

"""
    set_relations!(world::World, entity::Entity, relations::Tuple)

Sets relation targets for the given components of an [Entity](@ref).
The entity must already have all these relationship components.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
set_relations!(world, entity, (ChildOf => parent,))

# output

```
"""
@inline Base.@constprop :aggressive function set_relations!(world::W, entity::Entity, relations::Tuple) where {W<:World}
    if !is_alive(world, entity)
        throw(ArgumentError("can't set relation targets of a dead entity"))
    end
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _set_relations!(world, entity, rel_types, targets)
end

"""
    add_components!(world::World, entity::Entity, values::Tuple; relations::Tuple)

Adds the given component values to an [Entity](@ref). Types are inferred from the values.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
add_components!(world, entity, (Health(100),))

# output

```
"""
@inline Base.@constprop :aggressive function add_components!(
    world::World,
    entity::Entity,
    values::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    if !is_alive(world, entity)
        throw(ArgumentError("can't add components to a dead entity"))
    end
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _exchange_components!(world, entity, Val{typeof(values)}(), values, (), rel_types, targets)
end

"""
    remove_components!(world::World, entity::Entity, comp_types::Tuple)

Removes the given components from an [Entity](@ref).

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
remove_components!(world, entity, (Position, Velocity))

# output

```
"""
@inline Base.@constprop :aggressive function remove_components!(world::World, entity::Entity, comp_types::Tuple)
    if !is_alive(world, entity)
        throw(ArgumentError("can't remove components from a dead entity"))
    end
    return @inline _exchange_components!(
        world,
        entity,
        Val{Tuple{}}(),
        (),
        ntuple(i -> Val(comp_types[i]), length(comp_types)),
        (), (),
    )
end

"""
    exchange_components!(
        world::World,
        entity::Entity;
        add::Tuple=(),
        remove::Tuple=(),
        relations::Tuple=(),
    )

Adds and removes components on an [Entity](@ref). Types are inferred from the add values.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
exchange_components!(world, entity;
    add=(Health(100),),
    remove=(Position, Velocity),
)

# output

```
"""
@inline Base.@constprop :aggressive function exchange_components!(
    world::World,
    entity::Entity;
    add::Tuple=(),
    remove::Tuple=(),
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    if !is_alive(world, entity)
        throw(ArgumentError("can't exchange components on a dead entity"))
    end
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _exchange_components!(
        world,
        entity,
        Val{typeof(add)}(),
        add,
        ntuple(i -> Val(remove[i]), length(remove)),
        rel_types, targets,
    )
end

"""
    get_resource(world::World, res_type::Type{T})::T

Get the resource of type `T` from the world.
"""
function get_resource(world::World, res_type::Type{T})::T where T
    getindex(world._resources, res_type)::T
end

"""
    has_resource(world::World, res_type::Type{T})::Bool

Check if a resource of type `T` is in the world.
"""
function has_resource(world::World, res_type::Type)::Bool
    res_type in keys(world._resources)
end

"""
    add_resource!(world::World, res::T)::T

Add the given resource to the world.
Returns the newly added resource.
"""
function add_resource!(world::World, res::T)::T where T
    has_resource(world, T) && throw(ArgumentError(lazy"World already contains a resource of type $T"))
    setindex!(world._resources, res, T)
    return res
end

"""
    set_resource!(world::World, res::T)::T

Overwrites an existing resource in the world.
Returns the newly overwritten resource.
"""
function set_resource!(world::World, res::T)::T where T
    !has_resource(world, T) && throw(ArgumentError(lazy"World does not contain a resource of type $T"))
    setindex!(world._resources, res, T)
    return res
end

"""
    remove_resource!(world::World, res_type::Type{T})::T

Remove the resource of type `T` from the world.
Returns the removed resource.
"""
function remove_resource!(world::World, res_type::Type{T}) where T
    res = pop!(world._resources, res_type)
    return res::T
end

"""
    is_alive(world::World, entity::Entity)::Bool

Returns whether an [Entity](@ref) is alive.
"""
function is_alive(world::World, entity::Entity)::Bool
    return _is_alive(world._entity_pool, entity)
end

"""
    is_locked(world::World)::Bool

Returns whether the world is currently [locked](@ref world-lock) for modifications.
"""
function is_locked(world::World)::Bool
    return _is_locked(world._lock)
end

"""
    emit_event!(world::World, event::EventType, entity::Entity, components::Tuple=())

Emits a custom event for the given [EventType](@ref), [Entity](@ref) and optional components.
The entity must have the given components. The entity can be the reserved [zero_entity](@ref).

  - `world::World`: The [World](@ref) to emit the event.
  - `event::EventType`: The [EventType](@ref) to emit.
  - `entity::Entity`: The [Entity](@ref) to emit the event for.
  - `components::Tuple=()`: The component types to emit the event for. Optional.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
emit_event!(world, OnCollisionDetected, entity, (Position, Velocity))

# output

```
"""
@inline Base.@constprop :aggressive function emit_event!(
    world::W,
    event::EventType,
    entity::Entity,
    components::Tuple=(),
) where {W<:World}
    if event._id < _custom_events._id
        throw(ArgumentError("only custom events can be emitted manually"))
    end
    if !_has_observers(world._event_manager, event)
        return
    end
    _emit_event!(world, event, entity, ntuple(i -> Val(components[i]), length(components)))
    return nothing
end

"""
    reset!(world::World)

Removes all entities and resources from the world, and un-registers all observers.
Does NOT free reserved memory or remove archetypes.

Can be used to run systematic simulations without the need to re-allocate memory for each run.
Accelerates re-populating the world by a factor of 2-3.
"""
function reset!(world::W) where {W<:World}
    _check_locked(world)

    resize!(world._entities, 1)
    resize!(world._targets, 1)
    _reset!(world._entity_pool)
    _reset!(world._lock)
    _reset!(world._event_manager)
    _reset!(world._cache)

    for table in world._tables
        empty!(table)
        _clear!(table.filters)
        archetype = world._archetypes[table.archetype]
        for comp in archetype.components
            _clear_component_data!(world, comp, table.id)
        end
    end

    for archetype in world._archetypes
        _reset!(archetype)
    end

    empty!(world._resources)
    return nothing
end

function Base.show(io::IO, world::World{CS,CT}) where {CS<:Tuple,CT<:Tuple}
    comp_types = CT.parameters
    type_names = join(map(_format_type, comp_types), ", ")
    entities = sum(length(arch.entities) for arch in world._tables)
    print(io, "World(entities=$entities, comp_types=($type_names))")
end

@generated function _World_from_types(
    ::Val{CS},
    ::Val{ST},
    ::Val{MUT},
    initial_capacity::Int,
) where {CS<:Tuple,ST<:Tuple,MUT}
    types = CS.parameters
    storage_val_types = ST.parameters
    allow_mutable = MUT::Bool

    for (T, mode) in zip(types, storage_val_types)
        if !isconcretetype(T)
            throw(
                ArgumentError("can't use $(nameof(T)) as component as it is not a concrete type"),
            )
        end
        if !(mode <: StructArrayStorage || mode <: VectorStorage)
            throw(
                ArgumentError(
                    "$(nameof(mode)) is not a valid storage mode, must be StructArrayStorage or VectorStorage",
                ),
            )
        end
        if mode <: StructArrayStorage && fieldcount(T) == 0
            throw(
                ArgumentError("can't use StructArrayStorage for $(nameof(T)) because it has no fields"),
            )
        end
    end

    # Immutability checks
    for (T, mode) in zip(types, storage_val_types)
        if ismutabletype(T)
            if mode <: StructArrayStorage
                throw(
                    ArgumentError("Component type $(nameof(T)) must be immutable because it uses StructArray storage"),
                )
            elseif !allow_mutable
                throw(ArgumentError("Component type $(nameof(T)) must be immutable unless 'allow_mutable' is used"))
            end
        end
    end

    # Component type tuple
    component_types = map(T -> :(Type{$T}), types)
    component_tuple_type = :(Tuple{$(component_types...)})

    # Storage type logic (based on resolved Val{...} types)
    storage_types = Vector{Any}(undef, length(types))
    storage_exprs = Vector{Any}(undef, length(types))

    for i in 1:length(types)
        T = types[i]
        mode = storage_val_types[i]
        if mode <: StructArrayStorage
            storage_types[i] = :(_ComponentStorage{$T,_StructArray_type($T)})
            storage_exprs[i] = :(_new_struct_array_storage($T))
        else
            storage_types[i] = :(_ComponentStorage{$T,Vector{$T}})
            storage_exprs[i] = :(_new_vector_storage($T))
        end
    end

    # Final type and value tuples
    storage_tuple_type = :(Tuple{$(storage_types...)})
    storage_tuple = Expr(:tuple, storage_exprs...)

    storage_mode_type = :(Tuple{$(storage_val_types...)})

    # Component registration
    id_exprs = [:(_register_component!(registry, $T)) for T in types]
    id_tuple = Expr(:tuple, id_exprs...)

    relations_expr = [:(_new_component_relations($T <: Relationship)) for T in types]
    relations_vec = Expr(:vect, relations_expr...)

    M = max(1, cld(length(types), 64))
    start_mask = _Mask{M}()
    return quote
        registry = _ComponentRegistry()
        ids = $id_tuple
        graph = _Graph{$(M)}()
        index = _EntityIndex[_EntityIndex(typemax(UInt32), 0)]
        sizehint!(index, initial_capacity)
        targets = BitVector((false,))
        sizehint!(targets, initial_capacity)

        node = graph.nodes[$start_mask]

        World{$(storage_tuple_type),$(component_tuple_type),$(storage_mode_type),$(length(types)),$M}(
            index,
            targets,
            $storage_tuple,
            $relations_vec,
            [_Archetype(UInt32(1), node, UInt32(1))],
            [_ArchetypeHot(node, UInt32(1))],
            Vector{UInt32}(),
            [_new_table(UInt32(1), UInt32(1))],
            _ComponentIndex{$(M)}($(length(types))),
            registry,
            _EntityPool(UInt32(1024)),
            _Lock(),
            graph,
            Dict{DataType,Any}(),
            _EventManager{
                World{$(storage_tuple_type),$(component_tuple_type),$(storage_mode_type),$(length(types)),$M},
                $(M),
            }(),
            _Cache{$M}(),
            _WorldPool{$M}(),
            initial_capacity,
        )
    end
end

@generated function _component_id(::Type{CS}, ::Type{C})::Int where {CS<:Tuple,C}
    _generate_type_lookup(CS, C, i -> :($i))
end

@generated function _get_storage(world::World{CS}, ::Type{C}) where {CS<:Tuple,C}
    _generate_type_lookup(CS, C, i -> :(world._storages.$i))
end

@generated function _get_relations_storage(world::World{CS}, ::Type{C}) where {CS<:Tuple,C}
    _generate_type_lookup(CS, C, i -> :(world._relations[$i]))
end

@inline function _find_or_create_archetype!(
    world::World,
    start::_GraphNode,
    add::Tuple{Vararg{Int}},
    remove::Tuple{Vararg{Int}},
    relations::Tuple{Vararg{Int}},
    add_mask::_Mask,
    rem_mask::_Mask,
    use_map::Union{_NoUseMap,_UseMap},
)::Tuple{UInt32,Bool}
    node = _find_node(world._graph, start, add, remove, add_mask, rem_mask, use_map)

    if node.archetype[] == typemax(UInt32)
        table = ifelse(isempty(relations), UInt32(length(world._tables) + 1), UInt32(0))
        return (_create_archetype!(world, node, table), true)
    else
        return (node.archetype[], false)
    end
end

@inline function _find_or_create_table!(
    world::World,
    old_table::_Table,
    add::Tuple{Vararg{Int}},
    remove::Tuple{Vararg{Int}},
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
    add_mask::_Mask,
    rem_mask::_Mask,
    use_map::Union{_NoUseMap,_UseMap},
    world_has_rel::Val{true},
)::Tuple{UInt32,Bool}
    @inbounds old_arch = world._archetypes[old_table.archetype]
    new_arch_index, is_new = _find_or_create_archetype!(
        world, old_arch.node, add, remove, relations, add_mask, rem_mask, use_map,
    )
    @inbounds new_arch_hot = world._archetypes_hot[new_arch_index]

    if !new_arch_hot.has_relations && isempty(relations)
        if is_new
            @inbounds new_arch = world._archetypes[new_arch_index]
            return _create_table!(world, new_arch, _empty_relations), _has_relations(old_arch)
        end
        return new_arch_hot.table, _has_relations(old_arch)
    end

    @inbounds new_arch = world._archetypes[new_arch_index]
    return _find_or_create_table!(world, old_table, new_arch_hot, new_arch, relations, targets, !isempty(remove))
end

@inline function _find_or_create_table!(
    world::World,
    old_table::_Table,
    add::Tuple{Vararg{Int}},
    remove::Tuple{Vararg{Int}},
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
    add_mask::_Mask,
    rem_mask::_Mask,
    use_map::Union{_NoUseMap,_UseMap},
    world_has_rel::Val{false},
)::Tuple{UInt32,Bool}
    @inbounds old_arch = world._archetypes[old_table.archetype]
    new_arch_index, is_new = _find_or_create_archetype!(
        world, old_arch.node, add, remove, relations, add_mask, rem_mask, use_map,
    )
    @inbounds new_arch_hot = world._archetypes_hot[new_arch_index]
    if is_new
        @inbounds new_arch = world._archetypes[new_arch_index]
        return _create_table!(world, new_arch, _empty_relations), false
    end
    return new_arch_hot.table, false
end

# internal for handling relations
function _find_or_create_table!(
    world::World,
    old_table::_Table,
    new_arch_hot::_ArchetypeHot,
    new_arch::_Archetype,
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
    has_remove::Bool,
)::Tuple{UInt32,Bool}
    # Find existing relations that were not removed, and add new relations.
    all_relations = world._pool.relations
    requires_free = true
    relation_removed = false
    if _has_relations(old_table) || !isempty(relations)
        if has_remove > 0
            for rel in old_table.relations
                if _get_bit(new_arch_hot.mask, rel[1])
                    push!(all_relations, rel)
                else
                    relation_removed = true
                end
            end
            @inbounds for i in eachindex(relations)
                push!(all_relations, Pair(relations[i], targets[i]))
            end
        else
            if length(relations) > 0
                append!(all_relations, old_table.relations)
                @inbounds for i in eachindex(relations)
                    push!(all_relations, Pair(relations[i], targets[i]))
                end
            else
                all_relations = old_table.relations
                requires_free = false
            end
        end
    end

    new_table, found = _get_table(world, new_arch, all_relations)

    if found
        if requires_free
            empty!(all_relations)
        end
        return new_table.id, relation_removed
    end

    if length(all_relations) > 0
        sort!(all_relations; by=first)
    end

    new_table_id, found = _get_free_table!(new_arch)
    if found
        _recycle_table!(world, new_arch, new_table_id, all_relations)
    else
        new_table_id = _create_table!(world, new_arch, copy(all_relations))
    end
    if requires_free
        empty!(all_relations)
    end

    return new_table_id, relation_removed
end

function _recycle_table!(world::World, arch::_Archetype, table_id::UInt32, relations::Vector{Pair{Int,Entity}})
    if length(relations) < arch.num_relations
        throw(ArgumentError("relation targets must be fully specified"))
    end

    _check_relation_targets(world, relations)
    table = world._tables[table_id]

    for (i, comp) in enumerate(relations)
        entity = comp.second
        _activate_table_relation_for_comp!(world, comp.first, Int(table_id), entity)
        table.relations[i] = comp
        world._targets[entity._id] = true
    end

    _add_table!(world._relations, arch, table)
    _add_table!(world._cache, world, world._archetypes_hot[arch.id], table)
end

function _create_table!(world::World, arch::_Archetype, relations::Vector{Pair{Int,Entity}})::UInt32
    if length(relations) < arch.num_relations
        throw(ArgumentError("relation targets must be fully specified"))
    end
    # TODO: check that the archetype contains all components

    _check_relation_targets(world, relations)

    new_table_id = length(world._tables) + 1
    table = _new_table(UInt32(new_table_id), arch.id, world._initial_capacity, relations)
    push!(world._tables, table)

    _push_empty_to_all_storages!(world)
    for comp in arch.components
        _activate_new_column_for_comp!(world, comp, new_table_id)
    end

    _push_zero_to_all_table_relations!(world)
    for (i, comp) in enumerate(relations)
        entity = comp.second
        _activate_table_relation_for_comp!(world, comp.first, new_table_id, entity)
        world._targets[entity._id] = true
    end

    _add_table!(world._relations, arch, table)
    _add_table!(world._cache, world, world._archetypes_hot[arch.id], table)

    return UInt32(new_table_id)
end

function _create_archetype!(world::World, node::_GraphNode, table::UInt32)::UInt32
    components = _active_bit_indices(node.mask)
    relations = Int[]
    for id in components
        if _is_relation(world._registry, id)
            push!(relations, id)
        end
    end

    arch =
        _Archetype(UInt32(length(world._archetypes) + 1), node, table, relations, components...)
    push!(world._archetypes, arch)
    arch_hot = _ArchetypeHot(node, table, relations)
    push!(world._archetypes_hot, arch_hot)

    if _has_relations(arch)
        push!(world._relation_archetypes, arch.id)
    end

    index = length(world._archetypes)
    node.archetype[] = UInt32(index)

    _push_zero_to_all_archetype_relations!(world)

    for comp in arch.components
        push!(world._index.archetypes[comp], arch)
        push!(world._index.archetypes_hot[comp], arch_hot)
    end

    for (i, comp) in enumerate(relations)
        _activate_archetype_relation_for_comp!(world, comp, index, i)
    end

    return UInt32(index)
end

@inline function _get_exchange_targets(
    world::World,
    old_table::_Table,
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
)
    new_relations = world._pool.relations
    append!(new_relations, old_table.relations)

    changed = false
    mask = _clear_mask!(world._pool.mask)
    for (rel, trg) in zip(relations, targets)
        @inbounds target = world._relations[rel].targets[old_table.id]
        if target._id == 0
            throw(ArgumentError("entity does not have the requested relationship component"))
        end

        if target._id == trg._id
            continue
        end
        _set_bit!(mask, rel)
        @inbounds index = world._relations[rel].archetypes[old_table.archetype]
        @inbounds new_relations[index] = Pair(rel, trg)
        changed = true
    end

    return new_relations, changed, mask
end

# only for internal use in _cleanup_archetypes
function _get_exchange_targets_unchecked(
    world::World,
    old_table::_Table,
    relations::Vector{Pair{Int,Entity}},
)
    new_relations = world._pool.relations
    append!(new_relations, old_table.relations)

    mask = _clear_mask!(world._pool.mask)
    for (rel, trg) in relations
        @inbounds comp_relations = world._relations[rel]
        @inbounds target = comp_relations.targets[old_table.id]
        @inbounds index = comp_relations.archetypes[old_table.archetype]
        @inbounds new_relations[index] = Pair(rel, trg)

        if target._id != trg._id
            _set_bit!(mask, rel)
        end
    end

    return new_relations, mask
end

@inline function _get_table(world::World, arch::_Archetype, relations::Vector{Pair{Int,Entity}})::Tuple{_Table,Bool}
    if length(arch.tables) == 0
        return @inbounds world._tables[1], false
    end

    @check _has_relations(arch)

    if length(relations) < arch.num_relations
        throw(ArgumentError("relation targets must be fully specified"))
    end

    @inbounds first_rel = relations[1]
    rel_comp = first_rel.first
    target_id = first_rel.second._id

    @inbounds rel_idx = world._relations[rel_comp].archetypes[arch.id]
    index = arch.index[rel_idx]
    if !haskey(index, target_id)
        return @inbounds world._tables[1], false
    end

    @inbounds tables = index[target_id]
    if arch.num_relations == 1
        return @inbounds world._tables[tables.ids[1]], true
    end

    for table_id in tables.ids
        table = world._tables[table_id]
        if _matches_exact(world._relations, table, relations)
            return table, true
        end
    end

    return @inbounds world._tables[1], false
end

function _get_tables(world::World, arch::_Archetype, relations::Vector{Pair{Int,Entity}})::Vector{UInt32}
    if !_has_relations(arch) || isempty(relations)
        return arch.tables.ids
    end

    @inbounds first_rel = relations[1]
    rel_comp = first_rel.first
    target_id = first_rel.second._id

    @inbounds rel_idx = world._relations[rel_comp].archetypes[arch.id]
    @inbounds index = arch.index[rel_idx]
    if !haskey(index, target_id)
        return _empty_tables
    end

    return @inbounds index[target_id].ids
end

function _get_archetypes(world::World, ids::Tuple{Vararg{Int}})
    comps = world._index.archetypes
    hot = world._index.archetypes_hot
    rare_comp = @inbounds comps[ids[1]]
    rare_hot = @inbounds hot[ids[1]]
    min_len = length(rare_comp)
    @inbounds for i in 2:length(ids)
        comp = comps[ids[i]]
        comp_len = length(comp)
        if comp_len < min_len
            rare_comp, min_len = comp, comp_len
            rare_hot = hot[ids[i]]
        end
    end
    return rare_comp, rare_hot
end

function _cleanup_archetypes(world::World, entity::Entity)
    relations = Pair{Int,Entity}[]
    for arch in world._relation_archetypes
        archetype = world._archetypes[arch]
        if !haskey(archetype.target_tables, entity._id)
            continue
        end
        tables = archetype.target_tables[entity._id]

        for t in length(tables.ids):-1:1
            table_id = tables.ids[t]
            table = world._tables[table_id]
            has_target = false
            for rel in table.relations
                if rel.second._id == entity._id
                    push!(relations, Pair(rel.first, zero_entity))
                    has_target = true
                end
            end
            @check has_target == true

            if !isempty(table.entities)
                new_relations, mask = _get_exchange_targets_unchecked(world, table, relations)

                if _has_observers(world._event_manager, OnRemoveRelations)
                    _fire_set_relations(world._event_manager, OnRemoveRelations,
                        _BatchTable(table, archetype,
                            UInt32(1), UInt32(length(table)),
                        ),
                        mask)
                end

                new_table, found = _get_table(world, archetype, new_relations)
                if !found
                    new_table_id = _create_table!(world, archetype, copy(new_relations))
                    new_table = world._tables[new_table_id]
                end
                empty!(new_relations)

                start_index = length(new_table) + 1
                _move_entities!(world, table.id, new_table.id)

                if _has_observers(world._event_manager, OnAddRelations)
                    _fire_set_relations(world._event_manager, OnAddRelations,
                        _BatchTable(new_table, archetype,
                            UInt32(start_index), UInt32(length(new_table)),
                        ),
                        mask,
                    )
                end
            end
            _free_table!(archetype, table)
            _remove_table!(world._cache, table)
            empty!(relations)
        end
        _remove_target!(archetype, entity)
    end
end

@generated function _new_entity!(
    world::W,
    ::Val{TS},
    values::Tuple,
    ::TR,
    targets::Tuple{Vararg{Entity}},
) where {W<:World,TS<:Tuple,TR<:Tuple}
    types = _to_types(TS.parameters)
    rel_types = _to_types(TR)

    _check_no_duplicates(types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types)
    _check_is_subset(rel_types, types)

    CS = W.parameters[1]
    ids = tuple([_component_id(CS, T) for T in types]...)
    rel_ids = tuple([_component_id(CS, T) for T in rel_types]...)
    num_ids = length(ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(length(CS.parameters), 64))
    add_mask = _Mask{M}(ids...)
    rem_mask = _Mask{M}()

    world_has_rel = Val{_has_relations(CS)}()

    exprs = []
    push!(
        exprs,
        :(
            table = _find_or_create_table!(
                world,
                world._tables[1],
                $ids,
                (),
                $rel_ids,
                targets,
                $add_mask,
                $rem_mask,
                $use_map,
                $world_has_rel,
            )[1]
        ),
    )
    push!(exprs, :(tmp = _create_entity!(world, table)))
    push!(exprs, :(entity = tmp[1]))

    # Set each component
    for i in 1:length(types)
        T = types[i]
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        val_expr = :(values.$i)

        push!(exprs, :($stor_sym = _get_storage(world, $T)))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[table]))
        push!(exprs, :(push!($col_sym, $val_expr)))
    end

    push!(exprs, Expr(:return, Expr(:tuple, :entity, :table)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@inline @generated function _create_entity!(world::W, table_index::UInt32)::Tuple{Entity,Int} where {W<:World}
    CS = W.parameters[1]
    world_has_rel = _has_relations(CS)
    quote
        _check_locked(world)

        entity = _get_entity(world._entity_pool)
        @inbounds table = world._tables[table_index]
        @inbounds archetype = world._archetypes[table.archetype]

        index = _add_entity!(table, entity)

        if entity._id > length(world._entities)
            push!(world._entities, _EntityIndex(table_index, UInt32(index)))
            $(world_has_rel ? :(push!(world._targets, false)) : (:(nothing)))
        else
            @inbounds world._entities[Int(entity._id)] = _EntityIndex(table_index, UInt32(index))
            $(world_has_rel ? :(@inbounds world._targets[Int(entity._id)] = false) : (:(nothing)))
        end
        return entity, index
    end
end

@generated function _create_entities!(world::W, table_index::UInt32, n::UInt32)::Tuple{UInt32,UInt32} where {W<:World}
    CS = W.parameters[1]
    world_has_rel = _has_relations(CS)
    quote
        _check_locked(world)

        table = world._tables[Int(table_index)]
        archetype = world._archetypes[table.archetype]
        old_length = length(table.entities)
        new_length = old_length + n

        resize!(table, new_length)
        for i in (old_length+1):new_length
            entity = _get_entity(world._entity_pool)
            @inbounds table.entities._data[i] = entity

            if entity._id > length(world._entities)
                push!(world._entities, _EntityIndex(table_index, i))
                $(world_has_rel ? :(push!(world._targets, false)) : (:(nothing)))
            else
                @inbounds world._entities[Int(entity._id)] = _EntityIndex(table_index, i)
                $(world_has_rel ? :(@inbounds world._targets[Int(entity._id)] = false) : (:(nothing)))
            end
        end

        for comp in archetype.components
            _ensure_column_size_for_comp!(world, comp, table_index, new_length)
        end

        return (old_length + 1) % UInt32, new_length % UInt32
    end
end

@inline @generated function _move_entity!(
    world::W,
    entity::Entity,
    index::_EntityIndex,
    old_table::_Table,
    new_table::_Table,
    table_index::UInt32,
)::Int where {W<:World}
    inline_jtable = length(W.parameters[1].parameters) <= 10
    quote
        _check_locked(world)

        new_row = _add_entity!(new_table, entity)
        swapped = _swap_remove!(old_table.entities._data, index.row)

        if swapped
            @inbounds swap_entity = old_table.entities[index.row]
            @inbounds world._entities[swap_entity._id] = index
        end

        @inbounds world._entities[entity._id] = _EntityIndex(table_index, UInt32(new_row))

        @inbounds old_archetype = world._archetypes[old_table.archetype]
        @inbounds new_archetype = world._archetypes[new_table.archetype]

        # Move component data only for components present in old_archetype that are also present in new_archetype
        for comp in old_archetype.components
            if _get_bit(new_archetype.node.mask, comp)
                $(
                    inline_jtable ?
                    :(@inline _move_component_data!(world, comp, index.table, table_index, index.row)) :
                    :(_move_component_data!(world, comp, index.table, table_index, index.row))
                )
            else
                $(
                    inline_jtable ?
                    :(@inline _swap_remove_in_column_for_comp!(world, comp, index.table, index.row)) :
                    :(_swap_remove_in_column_for_comp!(world, comp, index.table, index.row))
                )
            end
        end

        return nothing
    end
end

function _move_entities!(world::World, old_table_index::UInt32, table_index::UInt32)
    _check_locked(world)
    old_table = world._tables[old_table_index]
    _move_entities!(world, old_table_index, table_index, UInt32(length(old_table.entities)))
end

function _move_entities!(world::World, old_table_index::UInt32, table_index::UInt32, num_entities::UInt32)
    old_table = world._tables[old_table_index]
    new_table = world._tables[table_index]
    old_archetype = world._archetypes[old_table.archetype]
    new_archetype = world._archetypes[new_table.archetype]

    old_entities = length(new_table.entities)
    total_entities = old_entities + num_entities

    resize!(new_table, total_entities)
    for comp in new_archetype.components
        _ensure_column_size_for_comp!(world, comp, table_index, total_entities)
    end

    for from in 1:num_entities
        to = old_entities + from
        entity = old_table.entities[from]
        new_table.entities._data[to] = entity
        world._entities[entity._id] = _EntityIndex(new_table.id, to)
    end
    for comp in old_archetype.components
        if _get_bit(new_archetype.node.mask, comp)
            _copy_component_data_to_end!(world, comp, old_table_index, table_index)
        end
        _clear_component_data!(world, comp, old_table_index)
    end

    empty!(old_table)
    return nothing
end

@inline @generated function _copy_entity!(world::W, entity::Entity, mode::Val)::Entity where {W<:World}
    inline_jtable = length(W.parameters[1].parameters) <= 10
    quote
        _check_locked(world)

        index = world._entities[entity._id]
        new_entity, new_row = _create_entity!(world, index.table)
        table = world._tables[index.table]
        archetype = world._archetypes[table.archetype]

        for comp in archetype.components
            $(
                inline_jtable ?
                :(@inline _copy_component_data!(world, comp, index.table, index.table, index.row, mode)) :
                :(_copy_component_data!(world, comp, index.table, index.table, index.row, mode))
            )
        end

        world._entities[new_entity._id] = _EntityIndex(index.table, UInt32(new_row))

        if _has_observers(world._event_manager, OnCreateEntity)
            _fire_create_entity(world._event_manager, new_entity, archetype.node.mask)
        end
        if _has_relations(archetype) && _has_observers(world._event_manager, OnAddRelations)
            _fire_create_entity_relations(world._event_manager, new_entity, archetype.node.mask)
        end
        return new_entity
    end
end

@generated function _copy_entity!(
    world::W,
    entity::Entity,
    ::Val{ATS},
    add::Tuple,
    ::RTS,
    ::TR,
    targets::Tuple{Vararg{Entity}},
    mode::CP,
)::Entity where {W<:World,ATS<:Tuple,RTS<:Tuple,TR<:Tuple,CP<:Val}
    add_types = _to_types(ATS.parameters)
    rem_types = _to_types(RTS)
    rel_types = _to_types(TR)
    exprs = []

    _check_no_duplicates(add_types)
    _check_no_duplicates(rem_types)
    _check_if_intersect(add_types, rem_types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types)
    _check_is_subset(rel_types, add_types)

    CS = W.parameters[1]
    add_ids = tuple([_component_id(CS, T) for T in add_types]...)
    rem_ids = tuple([_component_id(CS, T) for T in rem_types]...)
    rel_ids = tuple([_component_id(CS, T) for T in rel_types]...)

    num_ids = length(add_ids) + length(rem_ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(length(CS.parameters), 64))
    add_mask = _Mask{M}(add_ids...)
    rem_mask = _Mask{M}(rem_ids...)

    world_has_rel = Val{_has_relations(CS)}()
    push!(exprs, :(index = world._entities[entity._id]))
    push!(exprs, :(old_table = world._tables[index.table]))
    push!(exprs, :(old_archetype = world._archetypes[old_table.archetype]))
    push!(
        exprs,
        :(
            new_table_index =
                _find_or_create_table!(
                    world, old_table, $add_ids, $rem_ids, $rel_ids, targets, $add_mask, $rem_mask, $use_map,
                    $world_has_rel,
                )[1]
        ),
    )
    push!(exprs, :(new_table = world._tables[new_table_index]))
    push!(exprs, :(new_archetype = world._archetypes_hot[new_table.archetype]))

    push!(exprs, :(entity_and_row = _create_entity!(world, new_table_index)))
    push!(exprs, :(new_entity = entity_and_row[1]))

    push!(
        exprs,
        :(
            for comp in old_archetype.components
                if !_get_bit(new_archetype.mask, comp)
                    continue
                end
                _copy_component_data!(world, comp, index.table, new_table_index, index.row, mode)
            end
        ),
    )

    for i in 1:length(add_types)
        T = add_types[i]
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        val_expr = :(add.$i)

        push!(exprs, :($stor_sym = _get_storage(world, $T)))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[new_table_index]))
        push!(exprs, :(@inbounds push!($col_sym, $val_expr)))
    end

    push!(exprs, :(
        begin
            if _has_observers(world._event_manager, OnCreateEntity)
                _fire_create_entity(world._event_manager, new_entity, new_archetype.mask)
            end
            if new_archetype.has_relations && _has_observers(world._event_manager, OnAddRelations)
                _fire_create_entity_relations(world._event_manager, new_entity, new_archetype.mask)
            end
        end
    ))

    push!(exprs, Expr(:return, :new_entity))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _get_components(world::World, entity::Entity, ::TS) where {TS<:Tuple}
    types = _to_types(TS)
    if length(types) == 0
        return :(())
    end

    exprs = Expr[]
    push!(exprs, :(@inbounds idx = world._entities[entity._id]))

    for i in 1:length(types)
        T = types[i]
        stor_sym = Symbol("stor", i)
        val_sym = Symbol("v", i)

        push!(exprs, :($(stor_sym) = _get_storage(world, $T)))
        push!(exprs, :($(val_sym) = _get_component($(stor_sym), idx.table, idx.row)))
    end

    vals = [:($(Symbol("v", i))) for i in 1:length(types)]
    push!(exprs, Expr(:return, Expr(:tuple, vals...)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _has_components(world::World, index::_EntityIndex, ::TS) where {TS<:Tuple}
    types = _to_types(TS)
    exprs = []

    for i in 1:length(types)
        T = types[i]
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)

        push!(exprs, :($stor_sym = _get_storage(world, $T)))
        push!(exprs, :($col_sym = $stor_sym.data[index.table]))
        push!(exprs, :(
            if length($col_sym) == 0
                return false
            end
        ))
    end

    push!(exprs, :(return true))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _set_components!(world::World, entity::Entity, ::Val{TS}, values::Tuple) where {TS<:Tuple}
    types = TS.parameters
    exprs = [:(@inbounds idx = world._entities[entity._id])]

    for i in 1:length(types)
        T = types[i]
        stor_sym = Symbol("stor", i)
        val_expr = :(values.$i)

        push!(exprs, :($stor_sym = _get_storage(world, $T)))
        push!(exprs, :(_set_component!($stor_sym, idx.table, idx.row, $val_expr)))
    end

    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _get_relations(world::World, entity::Entity, ::TS) where {TS<:Tuple}
    types = _to_types(TS)
    if length(types) == 0
        return :(())
    end

    _check_relations(types)
    _check_no_duplicates(types)

    exprs = Expr[]
    push!(exprs, :(@inbounds idx = world._entities[entity._id]))

    for i in 1:length(types)
        T = types[i]
        target_sym = Symbol("t", i)

        push!(exprs, :($(target_sym) = @inbounds _get_relations_storage(world, $T).targets[idx.table]))
        push!(exprs, :(
            if $(target_sym)._id == 0
                tp = $T
                throw(ArgumentError(lazy"entity does not have relationship component $tp"))
            end
        ))
    end

    vals = [:($(Symbol("t", i))) for i in 1:length(types)]
    push!(exprs, Expr(:return, Expr(:tuple, vals...)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _set_relations!(
    world::W,
    entity::Entity,
    ::TR,
    targets::Tuple{Vararg{Entity}},
) where {W<:World,TR<:Tuple}
    rel_types = _to_types(TR)

    _check_no_duplicates(rel_types)
    _check_relations(rel_types)

    rel_ids = tuple([_component_id(W.parameters[1], T) for T in rel_types]...)

    exprs = []
    push!(exprs, :(_set_relations!(world, entity, $rel_ids, targets)))
    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@inline function _set_relations!(
    world::W,
    entity::Entity,
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
) where {W<:World}
    index = world._entities[entity._id]
    old_table = world._tables[index.table]
    archetype = world._archetypes[old_table.archetype]
    new_relations, changed, mask = _get_exchange_targets(world, old_table, relations, targets)
    if !changed
        empty!(new_relations)
        return nothing
    end

    new_table, found = _get_table(world, archetype, new_relations)
    if !found
        new_table_id = _create_table!(world, archetype, copy(new_relations))
        new_table = world._tables[new_table_id]
    end

    if _has_observers(world._event_manager, OnRemoveRelations)
        l = _lock(world._lock)
        _fire_set_relations(
            world._event_manager,
            OnRemoveRelations,
            entity,
            mask,
            world._archetypes_hot[new_table.archetype].mask,
            true,
        )
        _unlock(world._lock, l)
    end

    empty!(new_relations)
    _move_entity!(world, entity, index, old_table, new_table, new_table.id)

    if _has_observers(world._event_manager, OnAddRelations)
        _fire_set_relations(
            world._event_manager,
            OnAddRelations,
            entity,
            mask,
            world._archetypes_hot[new_table.archetype].mask,
            true,
        )
    end

    return nothing
end

@generated function _exchange_components!(
    world::W,
    entity::Entity,
    ::Val{ATS},
    add::Tuple,
    ::RTS,
    ::TR,
    targets::Tuple{Vararg{Entity}},
) where {W<:World,ATS<:Tuple,RTS<:Tuple,TR<:Tuple}
    add_types = _to_types(ATS.parameters)
    rem_types = _to_types(RTS)
    rel_types = _to_types(TR)

    if isempty(add_types) && isempty(rem_types)
        throw(ArgumentError("either components to add or to remove must be given for exchange_components!"))
    end

    _check_no_duplicates(add_types)
    _check_no_duplicates(rem_types)
    _check_if_intersect(add_types, rem_types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types)
    _check_is_subset(rel_types, add_types)

    exprs = []

    CS = W.parameters[1]
    add_ids = tuple([_component_id(CS, T) for T in add_types]...)
    rem_ids = tuple([_component_id(CS, T) for T in rem_types]...)
    rel_ids = tuple([_component_id(CS, T) for T in rel_types]...)

    num_ids = length(add_ids) + length(rem_ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(length(CS.parameters), 64))
    add_mask = _Mask{M}(add_ids...)
    rem_mask = _Mask{M}(rem_ids...)

    world_has_rel = Val{_has_relations(CS)}()

    push!(exprs, :(@inbounds index = world._entities[entity._id]))
    push!(exprs, :(@inbounds old_table = world._tables[index.table]))
    push!(
        exprs,
        :(
            new_table_tuple =
                _find_or_create_table!(
                    world, old_table, $add_ids, $rem_ids, $rel_ids, targets, $add_mask, $rem_mask, $use_map,
                    $world_has_rel,
                )
        ),
    )
    push!(exprs, :(new_table_index = new_table_tuple[1]))
    push!(exprs, :(@inbounds new_table = world._tables[new_table_index]))

    if length(rem_types) > 0
        push!(exprs, :(relations_removed = new_table_tuple[2]))
        push!(
            exprs,
            :(
                begin
                    has_comp_obs = _has_observers(world._event_manager, OnRemoveComponents)
                    has_rel_obs = relations_removed && _has_observers(world._event_manager, OnRemoveRelations)
                    if has_comp_obs || has_rel_obs
                        l = _lock(world._lock)
                        old_mask = world._archetypes_hot[old_table.archetype].mask
                        new_mask = world._archetypes_hot[new_table.archetype].mask
                        if has_comp_obs
                            _fire_remove(
                                world._event_manager,
                                OnRemoveComponents, entity,
                                old_mask, new_mask, true,
                            )
                        end
                        if has_rel_obs
                            _fire_remove(
                                world._event_manager,
                                OnRemoveRelations, entity,
                                old_mask, new_mask, true,
                            )
                        end
                        _unlock(world._lock, l)
                    end
                end
            ),
        )
    end

    push!(exprs, :(row = _move_entity!(world, entity, index, old_table, new_table, new_table_index)))
    for i in 1:length(add_types)
        T = add_types[i]
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        val_expr = :(add.$i)

        push!(exprs, :($stor_sym = _get_storage(world, $T)))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[new_table_index]))
        push!(exprs, :(push!($col_sym, $val_expr)))
    end

    if !isempty(add_types)
        push!(
            exprs,
            :(
                if _has_observers(world._event_manager, OnAddComponents)
                    _fire_add(
                        world._event_manager,
                        OnAddComponents, entity,
                        world._archetypes_hot[old_table.archetype].mask,
                        world._archetypes_hot[new_table.archetype].mask,
                        true,
                    )
                end
            ),
        )
        if !isempty(rel_types)
            push!(
                exprs,
                :(
                    if _has_observers(world._event_manager, OnAddRelations)
                        _fire_add(
                            world._event_manager,
                            OnAddRelations, entity,
                            world._archetypes_hot[old_table.archetype].mask,
                            world._archetypes_hot[new_table.archetype].mask,
                            true,
                        )
                    end
                ),
            )
        end
    end

    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _emit_event!(world::W, event::EventType, entity::Entity, ::CT) where {W<:World,CT<:Tuple}
    comp_types = [x.parameters[1] for x in CT.parameters]

    CS = W.parameters[1]
    has_comps = (length(comp_types) > 0) ? :(true) : (false)
    ids = map(C -> _component_id(CS, C), comp_types)
    M = max(1, cld(length(CS.parameters), 64))
    mask = _Mask{M}(ids...)

    return quote
        _do_emit_event!(world, event, $mask, $has_comps, entity)
    end
end

function _do_emit_event!(world::World, event::EventType, mask::_Mask, has_comps::Bool, entity::Entity)
    if is_zero(entity)
        if has_comps
            throw(ArgumentError("can't emit event with components for the zero entity"))
        end
        return _fire_custom_event(world._event_manager, event, entity, mask, world._archetypes_hot[1].mask)
    end

    if !is_alive(world, entity)
        throw(ArgumentError("can't emit event for a dead entity"))
    end
    index = world._entities[entity._id]
    table = world._tables[index.table]
    entity_mask = world._archetypes_hot[table.archetype].mask

    if !_contains_all(entity_mask, mask)
        throw(ArgumentError("entity does not have all components of the event emitted for it"))
    end
    return _fire_custom_event(world._event_manager, event, entity, mask, entity_mask)
end

@generated function _push_empty_to_all_storages!(world::World{CS,CT}) where {CS<:Tuple,CT<:Tuple}
    comp_types = CT.parameters
    n = length(comp_types)
    exprs = Expr[]
    for i in 1:n
        push!(exprs, :(_add_column!(world._storages.$i)))
    end
    return Expr(:block, exprs...)
end

@generated function _push_zero_to_all_archetype_relations!(world::World{CS,CT}) where {CS<:Tuple,CT<:Tuple}
    comp_types = CT.parameters
    n = length(comp_types)
    exprs = Expr[]
    for i in 1:n
        if comp_types[i].parameters[1] <: Relationship
            push!(exprs, :(_add_archetype_column!(world._relations[$i])))
        end
    end
    return Expr(:block, exprs...)
end

@generated function _push_zero_to_all_table_relations!(world::World{CS,CT}) where {CS<:Tuple,CT<:Tuple}
    comp_types = CT.parameters
    n = length(comp_types)
    exprs = Expr[]
    for i in 1:n
        if comp_types[i].parameters[1] <: Relationship
            push!(exprs, :(_add_table_column!(world._relations[$i])))
        end
    end
    return Expr(:block, exprs...)
end

@generated function _activate_new_column_for_comp!(world::World{CS}, comp::Int, index::Int) where CS
    _generate_component_switch(CS, :comp,
        i -> :(_activate_column!(world._storages.$i, index, world._initial_capacity)))
end

function _activate_archetype_relation_for_comp!(
    world::World{CS,CT},
    comp::Int,
    arch::Int,
    index::Int,
) where {CS,CT}
    _activate_archetype_column!(world._relations[comp], arch, index)
end

function _activate_table_relation_for_comp!(
    world::World{CS,CT},
    comp::Int,
    table::Int,
    target::Entity,
) where {CS,CT}
    _activate_table_column!(world._relations[comp], table, target)
end

@generated function _ensure_column_size_for_comp!(
    world::World{CS},
    comp::Int,
    arch::UInt32,
    needed::Int,
) where CS
    _generate_component_switch(CS, :comp,
        i -> :(_ensure_column_size!(world._storages.$i, arch, needed)))
end

@generated function _move_component_data!(
    world::World{CS},
    comp::Int,
    old_table::UInt32,
    new_table::UInt32,
    row::UInt32,
) where CS
    _generate_component_switch(CS, :comp,
        i -> :(_move_component_data!(world._storages.$i, old_table, new_table, row)))
end

@generated function _copy_component_data!(
    world::World{CS},
    comp::Int,
    old_table::UInt32,
    new_table::UInt32,
    old_row::UInt32,
    mode::CP,
) where {CS<:Tuple,CP<:Val}
    if !(CP in [Val{:ref}, Val{:copy}, Val{:deepcopy}])
        mode = CP.parameters[1]
        throw(ArgumentError(":$mode is not a valid copy mode, must be :ref, :copy or :deepcopy"))
    end
    _generate_component_switch(CS, :comp,
        i -> :(_copy_component_data!(world._storages.$i, old_table, new_table, old_row, mode)))
end

@generated function _copy_component_data_to_end!(
    world::World{CS},
    comp::Int,
    old_table::UInt32,
    new_table::UInt32,
) where {CS<:Tuple}
    _generate_component_switch(CS, :comp,
        i -> :(_copy_component_data_to_end!(world._storages.$i, old_table, new_table)))
end

@generated function _clear_component_data!(
    world::World{CS},
    comp::Int,
    table::UInt32,
) where {CS<:Tuple}
    _generate_component_switch(CS, :comp,
        i -> :(_clear_column!(world._storages.$i, table)))
end

@generated function _swap_remove_in_column_for_comp!(
    world::World{CS},
    comp::Int,
    table::UInt32,
    row::UInt32,
) where {CS<:Tuple}
    _generate_component_switch(CS, :comp,
        i -> :(_remove_component_data!(world._storages.$i, table, row)))
end

function _check_locked(world::World)
    if _is_locked(world._lock)
        throw(
            InvalidStateException(
                "cannot modify a locked world: collect entities into a vector and apply changes after query iteration has completed",
                :locked_world,
            ),
        )
    end
end

function _check_relation_targets(world::World, relations::Vector{Pair{Int,Entity}})
    for rel in relations
        _check_relation_target(world, rel.second)
    end
end

function _check_relation_target(world::World, target::Entity)
    if !is_zero(target) && !is_alive(world, target)
        throw(ArgumentError("can't use a dead entity as relation target, except for the zero entity"))
    end
end
