
mutable struct _QueryCursor
    closed::Bool
end

"""
    Query

A query for components. See function
[Query](@ref Query(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
"""
struct Query{QS<:Tuple,CT<:Tuple,OF,RO,M,K}
    _filter::_MaskFilter{M,K}
    _archetypes::Vector{_Archetype{M}}
    _archetypes_hot::Vector{_ArchetypeHot{M}}
    _q_lock::_QueryCursor
    _world_state::_WorldState{M,K}
    _storages::CT
    _empty_storages::QS
end

@inline function _check_query_world(world::World, query::Query)
    _state(world) === query._world_state || throw(ArgumentError("query belongs to a different world"))
    return nothing
end

"""
    Query(
        world::World,
        comp_types::Tuple;
        with::Tuple=(),
        without::Tuple=(),
        optional::Tuple=(),
        exclusive::Bool=false,
    )

Creates a query.

A query is an iterator for processing all entities that match the query's criteria.
The query itself iterates matching archetypes, while an inner loop or broadcast operations
must be used to manipulate individual entities (see example below).

A query [locks](@ref world-lock) the [World](@ref World) until it is fully iterated or closed manually.
This prevents structural changes like creating and removing entities or adding and removing components during the iteration.

See the user manual chapter on [Queries](@ref) for more details and examples.

# Arguments

  - `world`: The `World` instance to query.
  - `comp_types::Tuple`: Components the query filters for and provides access to. Relation targets can also be specified inline.
  - `with::Tuple`: Additional components the entities must have. Relation targets can be specified here as well.
  - `without::Tuple`: Components the entities must not have.
  - `optional::Tuple`: Additional components that are optional in the query.
  - `exclusive::Bool`: Makes the query exclusive in base and `with` components, can't be combined with `without`.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
for (entities, positions, velocities) in Query(world, (Position, Velocity))
    for i in eachindex(entities)
        pos = positions[i]
        vel = velocities[i]
        positions[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
    end
end

# output

```
"""
Base.@constprop :aggressive function Query(
    world::W,
    comp_types::Tuple;
    with::Tuple=(),
    without::Tuple=(),
    optional::Tuple=(),
    exclusive::Bool=false,
) where {W<:World}
    filter = Filter(
        world,
        comp_types;
        with=with,
        without=without,
        optional=optional,
        exclusive=exclusive,
    )
    return _Query_from_filter(world, filter)
end

"""
    Query(world::World, filter::Filter)

Creates a query from a [Filter](@ref).
"""
Base.@constprop :aggressive function Query(world::World, filter::Filter)
    return _Query_from_filter(world, filter)
end

function _mask_component_types(world_state::_WorldState, mask::_Mask)
    world_types = world_state._registry.types
    component_ids = _active_bit_indices(mask)
    return tuple(DataType[world_types[Int(id)] for id in component_ids]...)
end

function _format_mask_types(world_state::_WorldState, mask::_Mask)
    return join(map(_format_type, _mask_component_types(world_state, mask)), ", ")
end

function _format_mask_types_except(world_state::_WorldState, mask::_Mask, excluded_types::Tuple)
    types = setdiff(_mask_component_types(world_state, mask), excluded_types)
    return join(map(_format_type, types), ", ")
end

function _Query_from_filter_expr(::Type{W}, ::Type{F}) where {W<:World,F<:Filter}
    Storage = _world_storage(W)
    CM = _filter_component_mask(F)
    OM = _filter_optional_mask(F)
    M = _filter_mask_chunks(F)
    K = _filter_relation_count(F)
    output_ids = _filter_output_ids(F)
    output_readonly_mask = _filter_output_readonly_mask(F)

    component_ids = _active_bit_indices(CM)

    required_ids = Int[id for id in component_ids if !_get_bit(OM, id)]
    ids_tuple = tuple(required_ids...)

    # TODO: skip this for cached filters
    archetypes =
        length(ids_tuple) == 0 ?
        :((world_state._archetypes, world_state._archetypes_hot)) :
        :(_get_archetypes(world_state, $ids_tuple))

    query_optional_mask = _and(CM, OM)
    all_component_storage_types = fieldtypes(_schema_storage_types(Storage))
    query_storage_types = Any[all_component_storage_types[id] for id in output_ids]
    QS = Tuple{query_storage_types...}
    output_optional_ids = Int[i for i in eachindex(output_ids) if _get_bit(query_optional_mask, output_ids[i])]
    output_optional_mask = _Mask{M}(output_optional_ids...)
    CT = Tuple{map(A -> Vector{A}, query_storage_types)...}
    query_storages =
        Expr(:tuple, (_storage_ref(:world_storage, Storage, id) for id in output_ids)...)
    query_empties = Expr(:tuple, (_empty_ref(:world_storage, Storage, id) for id in output_ids)...)

    return quote
        _check_filter_world(world, filter)
        world_state = _state(world)
        world_storage = _storage(world)
        query_storages = $query_storages
        query_empties = $query_empties
        _lock(world_state._lock)
        arches, hot = $(archetypes)
        Query{$QS,$CT,$(QuoteNode(output_optional_mask)),$(QuoteNode(output_readonly_mask)),$M,$K}(
            filter._filter,
            arches,
            hot,
            _QueryCursor(false),
            world_state,
            query_storages,
            query_empties,
        )
    end
end

@generated function _Query_from_filter(
    world::W,
    filter::F,
) where {W<:World,F<:Filter}
    return _Query_from_filter_expr(W, F)
end

@inline function Base.iterate(q::Query, state::Tuple{Int,Int})
    if _is_cached(q._filter)
        return _iterate_registered(q, state)
    else
        return _iterate(q, state)
    end
end

@inline function _iterate(q::Query, state::Tuple{Int,Int})
    arch, tab = state
    world_state = q._world_state
    while arch <= length(q._archetypes)
        if tab == 0
            @inbounds archetype_hot = q._archetypes_hot[arch]

            if !_matches(q._filter, archetype_hot)
                arch += 1
                continue
            end

            if !archetype_hot.has_relations
                table = @inbounds world_state._tables[Int(archetype_hot.table)]
                if isempty(table.entities)
                    arch += 1
                    continue
                end
                result = _get_columns(q, table)
                return result, (arch + 1, 0)
            end

            @inbounds archetype = q._archetypes[arch]
            if isempty(archetype.tables.ids)
                arch += 1
                continue
            end

            tab = 1
        end

        @inbounds archetype = q._archetypes[arch]
        tables = _get_tables(world_state, archetype, q._filter.relations)

        while tab <= length(tables)
            table = @inbounds world_state._tables[Int(tables[tab])]
            # TODO we can probably optimize here if exactly one relation in archetype and one queried.
            if isempty(table.entities) || !_matches(world_state._relations, table, q._filter.relations)
                tab += 1
                continue
            end

            result = _get_columns(q, table)
            return result, (arch, tab + 1)
        end

        arch += 1
        tab = 0
    end

    close!(q)
    return nothing
end

@inline function _iterate_registered(q::Q, state::Tuple{Int,Int}) where {Q<:Query}
    index, _ = state
    world_state = q._world_state
    while index <= length(q._filter.tables)
        @inbounds table_id = q._filter.tables[index]
        @inbounds table = world_state._tables[table_id]
        if !isempty(table.entities)
            result = _get_columns(q, table)
            return result, (index + 1, 0)
        else
            index += 1
        end
    end
    close!(q)
    return nothing
end

@inline function Base.iterate(q::Query)
    if q._q_lock.closed
        throw(InvalidStateException("query closed, queries can't be used multiple times", :batch_closed))
    end

    return Base.iterate(q, (1, 0))
end

@inline function Base.first(q::Query)
    x = iterate(q)
    x === nothing && throw(ArgumentError("query must be non-empty"))
    return x[1]
end

@inline function Base.only(q::Query)
    firstv = iterate(q)
    if firstv === nothing
        throw(ArgumentError("query must contain exactly one matching table"))
    end

    table, state = firstv
    secondv = iterate(q, state)
    if secondv !== nothing
        close!(q)
        throw(ArgumentError("query must contain exactly one matching table"))
    end

    return table
end

function Base.length(q::Query)
    world_state = q._world_state
    if _is_cached(q._filter)
        return _length_registered(world_state, q._filter)
    else
        return _length(world_state, q._filter, q._archetypes, q._archetypes_hot)
    end
end

"""
    count_tables(world::World, q::Query)

Returns the number of matching tables with at least one entity in the query.

Does not iterate or [close!](@ref close!(::Query)) the query.

!!! note

    The time complexity is linear with the number of tables in the query's pre-selection.
"""
function count_tables(world::World, q::Query)
    _check_query_world(world, q)
    return length(q)
end

"""
    count_entities(world::World, q::Query)

Returns the number of matching entities in the query.

Does not iterate or [close!](@ref close!(::Query)) the query.

!!! note

    The time complexity is linear with the number of archetypes in the query's pre-selection.
    It is equivalent to iterating the query's archetypes and summing up their lengths.
"""
function count_entities(world::World, q::Query)
    _check_query_world(world, q)
    world_state = q._world_state
    if _is_cached(q._filter)
        return _count_entities_registered(world_state, q._filter)
    else
        return _count_entities(world_state, q._filter, q._archetypes, q._archetypes_hot)
    end
end

"""
    get_components(query::Query, entity::Entity, comp_types::Tuple)

Get the given components for an [Entity](@ref) through a [Query](@ref).
Components are returned as a tuple.

Only components which are part of the query can be accessed, optional and
[Const](@ref) ones included. The entity must match the query and have all the
requested components.

Does not iterate or [close!](@ref close!(::Query)) the query.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
query = Query(world, (Position, Velocity))
pos, vel = get_components(query, entity, (Position, Velocity))
close!(query)

# output

```
"""
@inline Base.@constprop :aggressive function get_components(
    query::Query,
    entity::Entity,
    comp_types::Tuple;
    _unchecked::Bool=false,
)
    return @inline _get_components(query, entity, _valtuple(comp_types), Val(_unchecked))
end

"""
    set_components!(query::Query, entity::Entity, values::Tuple)

Sets the given component values for an [Entity](@ref) through a [Query](@ref).
Types are inferred from the values.

Only components which are part of the query can be set, optional ones included.
Components marked as [Const](@ref) in the query are read-only and can't be set.
The entity must match the query and have all the given components.

Does not iterate or [close!](@ref close!(::Query)) the query.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
query = Query(world, (Position, Velocity))
set_components!(query, entity, (Position(0, 0), Velocity(1, 1)))
close!(query)

# output

```
"""
@inline Base.@constprop :aggressive function set_components!(
    query::Query,
    entity::Entity,
    values::Tuple;
    _unchecked::Bool=false,
)
    return @inline _set_components!(
        query,
        entity,
        Val{typeof(values)}(),
        values,
        Val(_unchecked),
    )
end

"""
    has_components(query::Query, entity::Entity, comp_types::Tuple)::Bool

Returns whether an [Entity](@ref) has all the given components.

Only components which are part of the query can be checked, optional and
[Const](@ref) ones included. An entity that does not match the query returns
`false`.

Does not iterate or [close!](@ref close!(::Query)) the query.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
query = Query(world, (Position, Velocity))
has = has_components(query, entity, (Position, Velocity))
close!(query)

# output

```
"""
@inline Base.@constprop :aggressive function has_components(
    query::Query,
    entity::Entity,
    comp_types::Tuple;
    _unchecked::Bool=false,
)
    return @inline _has_components(query, entity, _valtuple(comp_types), Val(_unchecked))
end

_query_component_types(::Type{QS}) where {QS<:Tuple} =
    DataType[_component_type(S) for S in fieldtypes(QS)]

function _query_component_index(query_types::Vector{DataType}, T::DataType)
    index = findfirst(==(T), query_types)
    if index === nothing
        available = join(map(_format_type, query_types), ", ")
        throw(ArgumentError(lazy"component $(_format_type(T)) is not part of the query on ($available)"))
    end
    return index
end

@noinline function _throw_missing_query_component(::Type{T}) where {T}
    throw(ArgumentError(lazy"entity has no $T component"))
end

@inline function _has_query_component(cols::Vector{A}, idx::_EntityIndex) where {A<:AbstractArray}
    table = Int(idx.table)
    return table <= length(cols) && length(@inbounds cols[table]) >= idx.row
end

@inline function _check_query_component(
    cols::Vector{A},
    idx::_EntityIndex,
    ::Type{T},
) where {A<:AbstractArray,T}
    if !_has_query_component(cols, idx)
        _throw_missing_query_component(T)
    end
    return nothing
end

@inline function _matches_query(q::Query, idx::_EntityIndex)
    world_state = q._world_state
    @inbounds table = world_state._tables[idx.table]
    @inbounds archetype = world_state._archetypes_hot[table.archetype]
    return _matches(q._filter, archetype) &&
           _matches(world_state._relations, table, q._filter.relations)
end

@noinline function _throw_entity_not_in_query()
    throw(ArgumentError("entity does not match query"))
end

@inline function _check_query_match(q::Query, idx::_EntityIndex)
    _matches_query(q, idx) || _throw_entity_not_in_query()
    return nothing
end

@generated function _get_components(
    q::Query{QS,CT,OF},
    entity::Entity,
    ::TS,
    ::Val{Unchecked},
) where {QS<:Tuple,CT<:Tuple,OF,TS<:Tuple,Unchecked}
    types = _to_types(TS)
    _check_no_duplicates(types)

    if length(types) == 0
        return :(())
    end

    query_types = _query_component_types(QS)
    indices = Int[_query_component_index(query_types, T) for T in types]

    exprs = Expr[]

    if !Unchecked
        push!(exprs, :(
            if !is_alive(q._world_state, entity)
                throw(ArgumentError("can't get components of a dead entity"))
            end
        ))
    end

    push!(exprs, :(@inbounds idx = q._world_state._entities[entity._id]))

    if !Unchecked
        push!(exprs, :(_check_query_match(q, idx)))
    end

    for i in eachindex(types)
        cols_sym = Symbol("cols", i)
        val_sym = Symbol("v", i)

        push!(exprs, :($cols_sym = q._storages[$(indices[i])]))
        if !Unchecked && _get_bit(OF, indices[i])
            push!(exprs, :(_check_query_component($cols_sym, idx, $(types[i]))))
        end
        push!(exprs, :($val_sym = _get_component($cols_sym, idx.table, idx.row)))
    end

    vals = Symbol[Symbol("v", i) for i in eachindex(types)]
    push!(exprs, Expr(:return, Expr(:tuple, vals...)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _has_components(
    q::Query{QS,CT,OF},
    entity::Entity,
    ::TS,
    ::Val{Unchecked},
) where {QS<:Tuple,CT<:Tuple,OF,TS<:Tuple,Unchecked}
    types = _to_types(TS)
    _check_no_duplicates(types)

    if length(types) == 0
        return :(true)
    end

    query_types = _query_component_types(QS)
    indices = Int[_query_component_index(query_types, T) for T in types]

    exprs = Expr[]

    if !Unchecked
        push!(exprs, :(
            if !is_alive(q._world_state, entity)
                throw(ArgumentError("can't check components of a dead entity"))
            end
        ))
    end

    push!(exprs, :(@inbounds idx = q._world_state._entities[entity._id]))

    checked_indices = Unchecked ? indices : Int[index for index in indices if _get_bit(OF, index)]
    checks = Expr[:(_has_query_component(q._storages[$index], idx)) for index in checked_indices]
    check_expr = isempty(checks) ? :(true) : foldr((a, b) -> Expr(:&&, a, b), checks)

    if !Unchecked
        push!(exprs, Expr(:return, :(_matches_query(q, idx) && $check_expr)))
    else
        push!(exprs, Expr(:return, check_expr))
    end

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _set_components!(
    q::Query{QS,CT,OF,RO},
    entity::Entity,
    ::Val{TS},
    values::Tuple,
    ::Val{Unchecked},
) where {QS<:Tuple,CT<:Tuple,OF,RO,TS<:Tuple,Unchecked}
    types = _to_types(fieldtypes(TS))
    _check_no_duplicates(types)

    if length(types) == 0
        return :(())
    end

    query_types = _query_component_types(QS)
    indices = Int[_query_component_index(query_types, T) for T in types]

    for i in eachindex(types)
        if _get_bit(RO, indices[i])
            throw(ArgumentError(lazy"component $(_format_type(types[i])) is read-only in the query"))
        end
    end

    exprs = Expr[]

    if !Unchecked
        push!(exprs, :(
            if !is_alive(q._world_state, entity)
                throw(ArgumentError("can't set components of a dead entity"))
            end
        ))
    end

    push!(exprs, :(@inbounds idx = q._world_state._entities[entity._id]))

    if !Unchecked
        push!(exprs, :(_check_query_match(q, idx)))
    end

    for i in eachindex(types)
        cols_sym = Symbol("cols", i)

        push!(exprs, :($cols_sym = q._storages[$(indices[i])]))
        if !Unchecked && _get_bit(OF, indices[i])
            push!(exprs, :(_check_query_component($cols_sym, idx, $(types[i]))))
        end
        push!(exprs, :(_set_component!($cols_sym, idx.table, idx.row, values[$i])))
    end

    push!(exprs, Expr(:return, :values))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

"""
    close!(q::Query)

Closes the query and unlocks the world.

Must be called if a query is not fully iterated.
"""
function close!(q::Query)
    if q._q_lock.closed == true
        return nothing
    end
    _unlock(q._world_state._lock)
    q._q_lock.closed = true
    return nothing
end

@generated function _get_columns(
    q::Query{QS,CT,OF,RO,M,K},
    table::_Table,
) where {QS<:Tuple,CT<:Tuple,OF,RO,M,K}
    component_storage_types = fieldtypes(QS)
    comp_types = map(_component_type, component_storage_types)
    storage_array_types = map(_storage_array_type, component_storage_types)
    N = length(component_storage_types)

    exprs = Expr[]
    push!(exprs, :(entities = table.entities))
    for i in 1:N
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        vec_sym = Symbol("vec", i)
        push!(exprs, :(@inbounds $stor_sym = q._storages[$i]))
        if _get_bit(OF, i)
            push!(
                exprs,
                :($col_sym = _column_or_empty($stor_sym, (@inbounds q._empty_storages[$i]), table.id)),
            )
        else
            push!(exprs, :(@inbounds $col_sym = $stor_sym[table.id]))
        end

        view_expr = if storage_array_types[i] <: GPUVector
            :(_gpuvector_view($col_sym, 1:($col_sym).len))
        elseif storage_array_types[i] <: StructArray ||
               storage_array_types[i] <: GPUStructArray ||
               storage_array_types[i] <: DiskStructArray ||
               fieldcount(comp_types[i]) == 0
            :(view($col_sym, :))
        else
            :(FieldViewable($col_sym))
        end
        if _get_bit(RO, i)
            view_expr = :(ReadOnly($view_expr))
        end
        if _get_bit(OF, i)
            push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : $view_expr))
        else
            push!(exprs, :($vec_sym = $view_expr))
        end
    end
    result_exprs = Symbol[:entities]
    for i in 1:N
        push!(result_exprs, Symbol("vec", i))
    end

    element_type = :(Base.eltype(Query{QS,CT,OF,RO,M,K}))

    tuple_expr = Expr(:tuple, result_exprs...)
    push!(exprs, Expr(:return, Expr(:(::), tuple_expr, element_type)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

Base.IteratorSize(::Type{<:Query}) = Base.HasLength()

@generated function Base.eltype(
    ::Type{<:Query{QS,CT,OF,RO,M,K}},
) where {QS<:Tuple,CT<:Tuple,OF,RO,M,K}
    component_storage_types = fieldtypes(QS)
    comp_types = map(_component_type, component_storage_types)
    storage_array_types = map(_storage_array_type, component_storage_types)
    N = length(component_storage_types)

    result_types = Any[:Entities]
    for i in 1:N
        T = comp_types[i]

        storage_type = storage_array_types[i]
        base_view = if storage_type <: GPUVector
            :(_gpuvectorview_type($storage_type))
        elseif fieldcount(comp_types[i]) == 0
            :(SubArray{$T,1,$storage_type,Tuple{Base.Slice{Base.OneTo{Int}}},IndexStyle($storage_type) == IndexLinear()})
        elseif storage_type <: StructArray
            :(_StructArrayView_type($T, UnitRange{Int}))
        elseif storage_type <: GPUStructArray
            :(_GPUStructArrayView_type($storage_type, UnitRange{Int}))
        elseif storage_type <: DiskStructArray
            :(_DiskStructArrayView_type($T, UnitRange{Int}))
        else
            :(_FieldsViewable_type($storage_type))
        end

        view_type = _get_bit(RO, i) ? :(_readonly_type($base_view)) : base_view

        push!(result_types, _get_bit(OF, i) ? :(Union{Nothing,$view_type}) : :($view_type))
    end

    return quote
        Tuple{$(result_types...)}
    end
end

function Base.show(io::IO, query::Query{QS,CT,OF,RO,M,K}) where {QS<:Tuple,CT<:Tuple,OF,RO,M,K}
    component_storage_types = fieldtypes(QS)
    comp_types = tuple(DataType[_component_type(S) for S in component_storage_types]...)
    display_types =
        tuple(DataType[_get_bit(RO, i) ? Const{comp_types[i]} : comp_types[i] for i in eachindex(comp_types)]...)

    required_types = tuple(DataType[display_types[i] for i in eachindex(display_types) if !_get_bit(OF, i)]...)
    optional_types = tuple(DataType[display_types[i] for i in eachindex(display_types) if _get_bit(OF, i)]...)

    required_names = join(map(_format_type, required_types), ", ")
    optional_names = join(map(_format_type, optional_types), ", ")
    with_names = _format_mask_types_except(query._world_state, query._filter.mask, comp_types)
    is_exclusive = query._filter.exclusive

    without_names = ""
    if !is_exclusive
        without_names = _format_mask_types(query._world_state, query._filter.exclude_mask)
    end

    kw_parts = String[]
    if !isempty(optional_types)
        push!(kw_parts, "optional=($optional_names)")
    end
    if !isempty(with_names)
        push!(kw_parts, "with=($with_names)")
    end
    if !isempty(without_names)
        push!(kw_parts, "without=($without_names)")
    end
    if is_exclusive
        push!(kw_parts, "exclusive=true")
    end

    if isempty(kw_parts)
        print(io, "Query(($required_names))")
    else
        print(io, "Query(($required_names); ", join(kw_parts, ", "), ")")
    end
end
