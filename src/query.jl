
mutable struct _QueryCursor
    tables::Vector{UInt32}
    closed::Bool
end

"""
    Query

A query for components. See function
[Query](@ref Query(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
"""
struct Query{W<:World,TS<:Tuple,SM<:Tuple,EX,OPT,REG,N,M}
    _filter::_MaskFilter{M}
    _archetypes::Vector{_Archetype{M}}
    _archetypes_hot::Vector{_ArchetypeHot{M}}
    _q_lock::_QueryCursor
    _world::W
    _lock::Int
end

"""
    Query(
        world::World,
        comp_types::Tuple;
        with::Tuple=(),
        without::Tuple=(),
        optional::Tuple=(),
        exclusive::Bool=false,
        relations::Tuple=(),
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
  - `comp_types::Tuple`: Components the query filters for and provides access to.
  - `with::Tuple`: Additional components the entities must have.
  - `without::Tuple`: Components the entities must not have.
  - `optional::Tuple`: Additional components that are optional in the query.
  - `exclusive::Bool`: Makes the query exclusive in base and `with` components, can't be combined with `without`.
  - `relations::Tuple`: Relationship component type => target entity pairs. These relation components must be in the query's components or `with`.

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
    world::World,
    comp_types::Tuple;
    with::Tuple=(),
    without::Tuple=(),
    optional::Tuple=(),
    exclusive::Bool=false,
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    filter = Filter(
        world,
        comp_types;
        with=with,
        without=without,
        optional=optional,
        exclusive=exclusive,
        relations=relations,
    )
    return _Query_from_filter(filter)
end

"""
    Query(filter::Filter)

Creates a query from a [Filter](@ref).
"""
Base.@constprop :aggressive function Query(
    filter::F,
) where {F<:Filter}
    return _Query_from_filter(filter)
end

@generated function _Query_from_filter(
    filter::F,
) where {F<:Filter}
    W = F.parameters[1]
    CS = W.parameters[1]
    TS = F.parameters[2]
    EX = F.parameters[3]
    OPT = F.parameters[4]
    REG = F.parameters[5]
    M = F.parameters[6]

    world_storage_modes = W.parameters[3].parameters
    comp_types = _to_types(TS.parameters)
    optional_flags = OPT.parameters

    storage_modes = [
        world_storage_modes[_component_id(W.parameters[1], T)]
        for T in comp_types
    ]
    storage_tuple_mode = Expr(:curly, :Tuple, storage_modes...)

    required_ids = [_component_id(CS, comp_types[i]) for i in 1:length(comp_types) if optional_flags[i] === Val{false}]
    ids_tuple = tuple(required_ids...)

    # TODO: skit this for cached filters
    archetypes =
        length(ids_tuple) == 0 ? :((filter._world._archetypes, filter._world._archetypes_hot)) :
        :(_get_archetypes(filter._world, $ids_tuple))

    return quote
        arches, hot = $(archetypes)
        Query{$W,$TS,$storage_tuple_mode,$EX,$OPT,$REG,$(length(comp_types)),$M}(
            filter._filter,
            arches,
            hot,
            _QueryCursor(_empty_tables, false),
            filter._world,
            _lock(filter._world._lock),
        )
    end
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
    while arch <= length(q._archetypes)
        if tab == 0
            @inbounds archetype_hot = q._archetypes_hot[arch]

            if !_matches(q._filter, archetype_hot)
                arch += 1
                continue
            end

            if !archetype_hot.has_relations
                table = @inbounds q._world._tables[Int(archetype_hot.table)]
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

            q._q_lock.tables = _get_tables(q._world, archetype, q._filter.relations)
            tab = 1
        end

        while tab <= length(q._q_lock.tables)
            table = @inbounds q._world._tables[Int(q._q_lock.tables[tab])]
            # TODO we can probably optimize here if exactly one relation in archetype and one queried.
            if isempty(table.entities) || !_matches(q._world._relations, table, q._filter.relations)
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
    if index <= length(q._filter.tables)
        @inbounds table_id = q._filter.tables[index]
        @inbounds table = q._world._tables[table_id]
        result = _get_columns(q, table)
        return result, (index + 1, 0)
    end
    close!(q)
    return nothing
end

@inline function Base.iterate(q::Q) where {Q<:Query}
    if q._q_lock.closed
        throw(InvalidStateException("query closed, queries can't be used multiple times", :batch_closed))
    end
    q._q_lock.closed = true

    return Base.iterate(q, (1, 0))
end

"""
    length(q::Query)

Returns the number of matching tables with at least one entity in the query.

Does not iterate or [close!](@ref close!(::Query)) the query.

!!! note

    The time complexity is linear with the number of tables in the query's pre-selection.
"""
function Base.length(q::Q) where {Q<:Query}
    if _is_cached(q._filter)
        return _length_registered(q._world, q._filter)
    else
        return _length(q._world, q._filter, q._archetypes, q._archetypes_hot)
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
    if _is_cached(q._filter)
        return _count_entities_registered(q._world, q._filter)
    else
        return _count_entities(q._world, q._filter, q._archetypes, q._archetypes_hot)
    end
end

"""
    close!(q::Query)

Closes the query and unlocks the world.

Must be called if a query is not fully iterated.
"""
function close!(q::Q) where {Q<:Query}
    _unlock(q._world._lock, q._lock)
    q._q_lock.closed = true
    return nothing
end

@generated function _get_columns(
    q::Query{W,TS,SM,EX,OPT,REG,N,M},
    table::_Table,
) where {W<:World,TS<:Tuple,SM<:Tuple,EX,OPT,REG,N,M}
    comp_types = TS.parameters
    storage_modes = SM.parameters
    is_optional = OPT.parameters

    exprs = Expr[]
    push!(exprs, :(entities = table.entities))
    for i in 1:N
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        vec_sym = Symbol("vec", i)
        push!(exprs, :(@inbounds $stor_sym = _get_storage(q._world, $(comp_types[i]))))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[table.id]))

        if is_optional[i] === Val{true}
            if storage_modes[i] == Storage{StructArray} || fieldcount(comp_types[i]) == 0
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : view($col_sym, :)))
            elseif storage_modes[i].parameters[1] <: GPUVector
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : view(($col_sym).mem, 1:($col_sym).len)))
            else
                push!(exprs, :($vec_sym = length($col_sym) == 0 ? nothing : FieldViewable($col_sym)))
            end
        else
            if storage_modes[i] == Storage{StructArray} || fieldcount(comp_types[i]) == 0
                push!(exprs, :($vec_sym = view($col_sym, :)))
            elseif storage_modes[i].parameters[1] <: GPUVector
                push!(exprs, :($vec_sym = view(($col_sym).mem, 1:($col_sym).len)))
            else
                push!(exprs, :($vec_sym = FieldViewable($col_sym)))
            end
        end
    end
    result_exprs = [:entities]
    for i in 1:N
        push!(result_exprs, Symbol("vec", i))
    end

    element_type = :(Base.eltype(Query{W,TS,SM,EX,OPT,REG,N,M}))

    result_exprs = map(x -> :($x), result_exprs)
    tuple_expr = Expr(:tuple, result_exprs...)
    push!(exprs, Expr(:return, Expr(:(::), tuple_expr, element_type)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

Base.IteratorSize(::Type{<:Query}) = Base.SizeUnknown()

@generated function Base.eltype(
    ::Type{Query{W,TS,SM,EX,OPT,REG,N,M}},
) where {W<:World,TS<:Tuple,SM<:Tuple,EX,OPT,REG,N,M}
    comp_types = TS.parameters
    storage_modes = SM.parameters
    is_optional = OPT.parameters

    result_types = Any[:Entities]
    for i in 1:N
        T = comp_types[i]

        ST = :(_storage_type($(storage_modes[i]), $T))
        base_view = if storage_modes[i].parameters[1] <: GPUVector
            :($(ST).parameters[3])
        elseif fieldcount(comp_types[i]) == 0
            :(SubArray{$T,1,$ST,Tuple{Base.Slice{Base.OneTo{Int}}},IndexStyle($ST) == IndexLinear()})
        elseif storage_modes[i] != Storage{StructArray}
            :(_FieldsViewable_type($ST))
        else
            :(_StructArrayView_type($T, UnitRange{Int}))
        end

        opt_flag = is_optional[i] === Val{true}
        push!(result_types, opt_flag ? :(Union{Nothing,$base_view}) : :($base_view))
    end

    return quote
        Tuple{$(result_types...)}
    end
end

function Base.show(io::IO, query::Query{W,CT,SM,EX}) where {W<:World,CT<:Tuple,SM<:Tuple,EX<:Val}
    world_types = W.parameters[2].parameters
    comp_types = CT.parameters

    mask_ids = _active_bit_indices(query._filter.mask)
    mask_types = tuple(map(i -> world_types[Int(i)].parameters[1], mask_ids)...)

    required_types = intersect(mask_types, comp_types)
    optional_types = setdiff(comp_types, mask_types)
    with_types = setdiff(mask_types, comp_types)

    required_names = join(map(_format_type, required_types), ", ")
    optional_names = join(map(_format_type, optional_types), ", ")
    with_names = join(map(_format_type, with_types), ", ")
    is_exclusive = EX === Val{true}

    excl_types = ()
    without_names = ""
    if !is_exclusive
        excl_ids = _active_bit_indices(query._filter.exclude_mask)
        excl_types = tuple(map(i -> world_types[Int(i)].parameters[1], excl_ids)...)
        without_names = join(map(_format_type, excl_types), ", ")
    end

    kw_parts = String[]
    if !isempty(optional_types)
        push!(kw_parts, "optional=($optional_names)")
    end
    if !isempty(with_types)
        push!(kw_parts, "with=($with_names)")
    end
    if !isempty(excl_types)
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
