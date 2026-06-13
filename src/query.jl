
mutable struct _QueryCursor
    closed::Bool
end

"""
    Query

A query for components. See function
[Query](@ref Query(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
"""
struct Query{State<:_WorldState,QS<:Tuple,EX,OF,M,K}
    _filter::_MaskFilter{M,K}
    _archetypes::Vector{_Archetype{M}}
    _archetypes_hot::Vector{_ArchetypeHot{M}}
    _q_lock::_QueryCursor
    _world_state::State
    _storages::QS
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
    comp_types_f, _ = _normalize_relations(comp_types, Val(:type))
    optional_f, _ = _normalize_relations(optional, Val(:type))
    filter = Filter(
        world,
        comp_types;
        with=with,
        without=without,
        optional=optional,
        exclusive=exclusive,
    )
    return _Query_from_filter(world, filter, _valtuple(comp_types_f), _valtuple(optional_f))
end

"""
    Query(world::World, filter::Filter)

Creates a query from a [Filter](@ref).
"""
Base.@constprop :aggressive function Query(
    world::World,
    filter::F,
) where {F<:Filter}
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

function _Query_from_filter_expr(::Type{F}, output_ids::Tuple{Vararg{Int}}) where {F<:Filter}
    W = _filter_world(F)
    Storage = _world_storage(W)
    State = fieldtype(W, :_state)
    CM = _filter_component_mask(F)
    EX = _filter_exclusive(F)
    OM = _filter_optional_mask(F)
    M = _filter_mask_chunks(F)
    K = _filter_relation_count(F)

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
    query_storages = Expr(:tuple, (:(world_storage._storages[$id]) for id in output_ids)...)

    return quote
        _check_filter_world(world, filter)
        world_state = _state(world)
        world_storage = _storage(world)
        query_storages = $query_storages
        _lock(world_state._lock)
        arches, hot = $(archetypes)
        Query{$State,$QS,$EX,$(QuoteNode(output_optional_mask)),$M,$K}(
            filter._filter,
            arches,
            hot,
            _QueryCursor(false),
            world_state,
            query_storages,
        )
    end
end

@generated function _Query_from_filter(
    world::World,
    filter::F,
) where {F<:Filter}
    output_ids = _filter_output_ids(F)
    return _Query_from_filter_expr(F, output_ids)
end

@generated function _Query_from_filter(
    world::World,
    filter::F,
    ::CT,
    ::OT,
) where {F<:Filter,CT<:Tuple,OT<:Tuple}
    W = _filter_world(F)
    CS = _world_storage_types(W)

    required_types = _to_types(CT)
    optional_types = _to_types(OT)
    output_ids = tuple(Int[_component_index(CS, C) for C in (required_types..., optional_types...)]...)

    return _Query_from_filter_expr(F, output_ids)
end

@inline function Base.iterate(q::Q, state::Tuple{Int,Int}) where {Q<:Query}
    if _is_cached(q._filter)
        return _iterate_registered(q, state)
    else
        return _iterate(q, state)
    end
end

@inline function _iterate(q::Q, state::Tuple{Int,Int}) where {Q<:Query}
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

@inline function Base.iterate(q::Q) where {Q<:Query}
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

"""
    length(q::Query)

Returns the number of matching tables with at least one entity in the query.

Does not iterate or [close!](@ref close!(::Query)) the query.

!!! note

    The time complexity is linear with the number of tables in the query's pre-selection.
"""
function Base.length(q::Q) where {Q<:Query}
    world_state = q._world_state
    if _is_cached(q._filter)
        return _length_registered(world_state, q._filter)
    else
        return _length(world_state, q._filter, q._archetypes, q._archetypes_hot)
    end
end

"""
    count_entities(q::Query)

Returns the number of matching entities in the query.

Does not iterate or [close!](@ref close!(::Query)) the query.

!!! note

    The time complexity is linear with the number of archetypes in the query's pre-selection.
    It is equivalent to iterating the query's archetypes and summing up their lengths.
"""
function count_entities(q::Q) where {Q<:Query}
    world_state = q._world_state
    if _is_cached(q._filter)
        return _count_entities_registered(world_state, q._filter)
    else
        return _count_entities(world_state, q._filter, q._archetypes, q._archetypes_hot)
    end
end

"""
    close!(q::Query)

Closes the query and unlocks the world.

Must be called if a query is not fully iterated.
"""
function close!(q::Q) where {Q<:Query}
    if q._q_lock.closed == true
        return nothing
    end
    _unlock(q._world_state._lock)
    q._q_lock.closed = true
    return nothing
end

@generated function _get_columns(
    q::Query{State,QS,EX,OF,M,K},
    table::_Table,
) where {State<:_WorldState,QS<:Tuple,EX,OF,M,K}
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
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[table.id]))

        if _get_bit(OF, i)
            if storage_array_types[i] <: GPUVector
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : view(($col_sym).mem, 1:($col_sym).len)))
            elseif storage_array_types[i] <: StructArray ||
                   storage_array_types[i] <: GPUStructArray ||
                   fieldcount(comp_types[i]) == 0
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : view($col_sym, :)))
            else
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : FieldViewable($col_sym)))
            end
        else
            if storage_array_types[i] <: GPUVector
                push!(exprs, :($vec_sym = view(($col_sym).mem, 1:($col_sym).len)))
            elseif storage_array_types[i] <: StructArray ||
                   storage_array_types[i] <: GPUStructArray ||
                   fieldcount(comp_types[i]) == 0
                push!(exprs, :($vec_sym = view($col_sym, :)))
            else
                push!(exprs, :($vec_sym = FieldViewable($col_sym)))
            end
        end
    end
    result_exprs = Symbol[:entities]
    for i in 1:N
        push!(result_exprs, Symbol("vec", i))
    end

    element_type = :(Base.eltype(Query{State,QS,EX,OF,M,K}))

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
    ::Type{Query{State,QS,EX,OF,M,K}},
) where {State<:_WorldState,QS<:Tuple,EX,OF,M,K}
    component_storage_types = fieldtypes(QS)
    comp_types = map(_component_type, component_storage_types)
    storage_array_types = map(_storage_array_type, component_storage_types)
    N = length(component_storage_types)

    result_types = Any[:Entities]
    for i in 1:N
        T = comp_types[i]

        storage_type = storage_array_types[i]
        base_view = if storage_type <: GPUVector
            B = Val{_gpu_backend(storage_type)}()
            :(_gpuvectorview_type($T, $B))
        elseif fieldcount(comp_types[i]) == 0
            :(SubArray{$T,1,$storage_type,Tuple{Base.Slice{Base.OneTo{Int}}},IndexStyle($storage_type) == IndexLinear()})
        elseif storage_type <: StructArray
            :(_StructArrayView_type($T, UnitRange{Int}))
        elseif storage_type <: GPUStructArray
            B = Val{_gpu_backend(storage_type)}()
            :(_GPUStructArrayView_type($T, UnitRange{Int}, $B))
        else
            :(_FieldsViewable_type($storage_type))
        end

        push!(result_types, _get_bit(OF, i) ? :(Union{Nothing,$base_view}) : :($base_view))
    end

    return quote
        Tuple{$(result_types...)}
    end
end

function Base.show(
    io::IO, query::Query{State,QS,EX,OF,M,K},
) where {State<:_WorldState,QS<:Tuple,EX,OF,M,K}
    component_storage_types = fieldtypes(QS)
    comp_types = tuple(DataType[_component_type(S) for S in component_storage_types]...)

    required_types = tuple(DataType[comp_types[i] for i in eachindex(comp_types) if !_get_bit(OF, i)]...)
    optional_types = tuple(DataType[comp_types[i] for i in eachindex(comp_types) if _get_bit(OF, i)]...)

    required_names = join(map(_format_type, required_types), ", ")
    optional_names = join(map(_format_type, optional_types), ", ")
    with_names = _format_mask_types_except(query._world_state, query._filter.mask, comp_types)
    is_exclusive = EX === true

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
