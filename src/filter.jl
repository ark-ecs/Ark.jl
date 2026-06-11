
"""
    Filter

A filter for components. See function
[Filter](@ref Filter(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
See also [Query](@ref).
"""
struct Filter{W<:World,TS<:Tuple,EX,OPT,REG,M,K}
    _filter::_MaskFilter{M,K}
    _world::W
end

@inline _filter_world(::Type{<:Filter{W}}) where {W} = W
@inline _filter_component_types(::Type{<:Filter{W,TS}}) where {W,TS} = TS
@inline _filter_exclusive(::Type{<:Filter{W,TS,EX}}) where {W,TS,EX} = EX
@inline _filter_optional_flags(::Type{<:Filter{W,TS,EX,OPT}}) where {W,TS,EX,OPT} = OPT
@inline _filter_registered(::Type{<:Filter{W,TS,EX,OPT,REG}}) where {W,TS,EX,OPT,REG} = REG
@inline _filter_mask_chunks(::Type{<:Filter{W,TS,EX,OPT,REG,M}}) where {W,TS,EX,OPT,REG,M} = M
@inline _filter_relation_count(::Type{<:Filter{W,TS,EX,OPT,REG,M,K}}) where {W,TS,EX,OPT,REG,M,K} = K

"""
    Filter(
        world::World,
        comp_types::Tuple;
        with::Tuple=(),
        without::Tuple=(),
        optional::Tuple=(),
        exclusive::Bool=false,
        register::Bool=false,
    )

Creates a filter.
Filters are similar to [queries](@ref Query), but can't be iterated directly.
They are a re-usable way to define query filtering criteria, and can be registered for faster, cached queries.
Further, filters are used in [batch operations](@ref "Batch operations").

See the user manual chapter on [Queries](@ref) for more details and examples.

# Arguments

  - `world`: The `World` instance to filter.
  - `comp_types::Tuple`: Components the filter filters for. Relation targets can also be specified.
  - `with::Tuple`: Additional components the entities must have. Relation targets can be specified here as well.
  - `without::Tuple`: Components the entities must not have.
  - `optional::Tuple`: Additional components that are optional in the filter.
  - `exclusive::Bool`: Makes the filter exclusive in base and `with` components, can't be combined with `without`.
"""
Base.@constprop :aggressive function Filter(
    world::World,
    comp_types::Tuple;
    with::Tuple=(),
    without::Tuple=(),
    optional::Tuple=(),
    exclusive::Bool=false,
    register::Bool=false,
)
    comp_types_f, comp_relations = _normalize_relations(comp_types, Val(:type))
    with_f, with_relations = _normalize_relations(with, Val(:type))
    relations = (comp_relations..., with_relations...)
    rel_types, targets = _relation_types_and_targets(relations)
    return _Filter_from_types(
        world,
        _valtuple(comp_types_f),
        _valtuple(with_f),
        _valtuple(without),
        _valtuple(optional),
        Val(exclusive),
        Val(register),
        rel_types,
        targets,
    )
end

@generated function _Filter_from_types(
    world::W,
    ::CT,
    ::WT,
    ::WO,
    ::OT,
    ::EX,
    ::REG,
    ::TR,
    targets::Tuple{Vararg{Entity}},
) where {W<:World,CT<:Tuple,WT<:Tuple,WO<:Tuple,OT<:Tuple,EX<:Val,REG<:Val,TR<:Tuple}
    relation_types = _world_relation_types(W)

    required_types = _to_types(CT)
    with_types = _to_types(WT)
    without_types = _to_types(WO)
    optional_types = _to_types(OT)
    rel_types = _to_types(TR)

    # check for duplicates
    all_comps = vcat(required_types, with_types, without_types, optional_types)
    _check_no_duplicates(all_comps)

    _check_no_duplicates(rel_types)
    _check_relations(rel_types, relation_types)

    comp_types = union(required_types, optional_types)
    non_exclude_types = union(comp_types, with_types)

    _check_is_subset(rel_types, union(required_types, with_types))

    if EX === Val{true} && !isempty(without_types)
        throw(ArgumentError("cannot use 'exclusive' together with 'without'"))
    end

    CS = _world_storage_types(W)
    required_ids = Int[_component_index(CS, C) for C in required_types]
    with_ids = Int[_component_index(CS, C) for C in with_types]
    without_ids = Int[_component_index(CS, C) for C in without_types]
    non_exclude_ids = Int[_component_index(CS, C) for C in non_exclude_types]
    rel_ids = Int[_component_index(CS, C) for C in rel_types]

    M = max(1, cld(fieldcount(CS), 64))
    K = fieldcount(relation_types)
    mask = _Mask{M}(required_ids..., with_ids...)
    exclude_mask = EX === Val{true} ? _Mask{M}(_Not(), non_exclude_ids...) : _Mask{M}(without_ids...)
    has_excluded = (length(without_ids) > 0) || (EX === Val{true})
    register = REG === Val{true}

    comp_tuple_type = Expr(:curly, :Tuple, comp_types...)

    optional_flag_type_elts = Expr[
        (T in optional_types) ? :(Val{true}) : :(Val{false})
        for T in comp_types
    ]
    optional_flags_type = Expr(:curly, :Tuple, optional_flag_type_elts...)

    relation_id_exprs = Expr(:tuple)
    relation_target_exprs = Expr(:tuple)
    for i in 1:K
        id_expr = i <= length(rel_ids) ? :($(Int32(rel_ids[i]))) : :(Int32(0))
        target_expr = i <= length(rel_ids) ? :(targets[$i]) : :(zero_entity)
        push!(relation_id_exprs.args, id_expr)
        push!(relation_target_exprs.args, target_expr)
    end
    relations_expr =
        :(_FilterRelations{$K}($(length(rel_ids)), $relation_id_exprs, $relation_target_exprs))

    return quote
        filter = Filter{$W,$comp_tuple_type,$EX,$optional_flags_type,$REG,$M,$K}(
            _MaskFilter{$M,$K}(
                $(mask),
                $(exclude_mask),
                $relations_expr,
                $register ? _IdCollection() : _empty_table_ids,
                Base.RefValue{UInt32}(UInt32(0)),
                $(has_excluded),
            ),
            world,
        )
        if $register
            _register_filter!(world, filter._filter)
        end
        return filter
    end
end

"""
    unregister!(world::World, filter::Filter)

Un-registers a [Filter](@ref).
"""
function unregister!(world::World, filter::Filter)
    _unregister_filter!(filter._world, filter._filter)
end

function _matches(filter::F, archetype::_ArchetypeHot) where {F<:_MaskFilter}
    return _contains_all(archetype.mask, filter.mask) &&
           (!filter.has_excluded || !_contains_any(archetype.mask, filter.exclude_mask))
end

macro _each_matching_table(world, filter, archetypes, archetypes_hot, table, action)
    esc(quote
        world_state = _state($world)
        for i in eachindex($(archetypes))
            archetype_hot = @inbounds $(archetypes_hot)[i]
            if !_matches($(filter), archetype_hot)
                continue
            end

            if !archetype_hot.has_relations
                table_id = archetype_hot.table
                $table = @inbounds world_state._tables[Int(table_id)]
                if !isempty($table.entities)
                    $action
                end
                continue
            end

            archetype = @inbounds $(archetypes)[i]
            if isempty(archetype.tables)
                continue
            end

            tables = _get_tables($world, archetype, $(filter).relations)
            for table_id in tables
                # TODO we can probably optimize here if exactly one relation in archetype and one queried.
                $table = @inbounds world_state._tables[Int(table_id)]
                if !isempty($table.entities) && _matches(world_state._relations, $table, $(filter).relations)
                    $action
                end
            end
        end
    end)
end

"""
    length(f::Filter)

Returns the number of matching tables with at least one entity in the filter.

!!! note

    The time complexity is linear with the number of tables in the filter's pre-selection.
"""
function Base.length(f::F) where {F<:Filter}
    if _is_cached(f._filter)
        return _length_registered(f._world, f._filter)
    else
        arches, arches_hot = _get_archetypes(f._world, f)
        return _length(f._world, f._filter, arches, arches_hot)
    end
end

function _length(
    world::W,
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M,K}
    count = 0
    @_each_matching_table(world, filter, archetypes, archetypes_hot, table, count += 1)
    return count
end

function _length_registered(world::W, filter::_MaskFilter{M,K}) where {W<:World,M,K}
    count = 0
    world_state = _state(world)
    @simd for table_id in filter.tables.ids
        table = @inbounds world_state._tables[table_id]
        count += (!isempty(table.entities)) % Int
    end
    return count
end

"""
    count_entities(f::Filter)

Returns the number of matching entities in the filter.

!!! note

    The time complexity is linear with the number of archetypes in the filter's pre-selection.
    It is equivalent to iterating the filter's archetypes and summing up their lengths.
"""
function count_entities(f::F) where {F<:Filter}
    if _is_cached(f._filter)
        return _count_entities_registered(f._world, f._filter)
    else
        arches, arches_hot = _get_archetypes(f._world, f)
        return _count_entities(f._world, f._filter, arches, arches_hot)
    end
end

function _count_entities(
    world::W,
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M,K}
    count = 0
    @_each_matching_table(world, filter, archetypes, archetypes_hot, table, count += length(table.entities))
    return count
end

function _count_entities_registered(world::W, filter::_MaskFilter{M,K}) where {W<:World,M,K}
    count = 0
    world_state = _state(world)
    @simd for table_id in filter.tables.ids
        table = @inbounds world_state._tables[table_id]
        count += length(table.entities)
    end
    return count
end

function Base.show(io::IO, filter::Filter{W,CT,EX,OPT,REG,M,K}) where {W<:World,CT<:Tuple,EX<:Val,OPT,REG<:Val,M,K}
    world_types = fieldtypes(_world_component_types(W))
    comp_types = fieldtypes(CT)

    mask_ids = _active_bit_indices(filter._filter.mask)
    mask_types = tuple(DataType[_type_parameter(world_types[Int(i)]) for i in mask_ids]...)

    required_types = intersect(mask_types, comp_types)
    optional_types = setdiff(comp_types, mask_types)
    with_types = setdiff(mask_types, comp_types)

    required_names = join(map(_format_type, required_types), ", ")
    optional_names = join(map(_format_type, optional_types), ", ")
    with_names = join(map(_format_type, with_types), ", ")
    is_exclusive = EX === Val{true}
    registered = REG === Val{true}

    excl_types = ()
    without_names = ""
    if !is_exclusive
        excl_ids = _active_bit_indices(filter._filter.exclude_mask)
        excl_types = tuple(DataType[_type_parameter(world_types[Int(i)]) for i in excl_ids]...)
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
    if registered
        push!(kw_parts, "registered=true")
    end

    if isempty(kw_parts)
        print(io, "Filter(($required_names))")
    else
        print(io, "Filter(($required_names); ", join(kw_parts, ", "), ")")
    end
end
