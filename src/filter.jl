
"""
    Filter

A filter for components. See function
[Filter](@ref Filter(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
See also [Query](@ref).
"""
struct Filter{W<:World,CM,EX,OM,M,K}
    _filter::_MaskFilter{M,K}
    _world::W
end

@inline _filter_world(::Type{<:Filter{W}}) where {W} = W
@inline _filter_component_mask(::Type{<:Filter{W,CM}}) where {W,CM} = CM
@inline _filter_exclusive(::Type{<:Filter{W,CM,EX}}) where {W,CM,EX} = EX
@inline _filter_optional_mask(::Type{<:Filter{W,CM,EX,OM}}) where {W,CM,EX,OM} = OM
@inline _filter_mask_chunks(::Type{<:Filter{W,CM,EX,OM,M}}) where {W,CM,EX,OM,M} = M
@inline _filter_relation_count(::Type{<:Filter{W,CM,EX,OM,M,K}}) where {W,CM,EX,OM,M,K} = K

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
    world::W,
    comp_types::Tuple;
    with::Tuple=(),
    without::Tuple=(),
    optional::Tuple=(),
    exclusive::Bool=false,
    register::Bool=false,
) where {W<:World}
    comp_types_f, comp_relations = _normalize_relations(comp_types, Val(:type))
    with_f, with_relations = _normalize_relations(with, Val(:type))
    relations = (comp_relations..., with_relations...)
    rel_types, targets = _relation_types_and_targets(relations)
    filter_type, mask_filter = _Filter_from_types(
        W,
        _valtuple(comp_types_f),
        _valtuple(with_f),
        _valtuple(without),
        _valtuple(optional),
        Val(exclusive),
        Val(register),
        rel_types,
        targets,
    )
    filter = filter_type(mask_filter, world)
    if register
        _register_filter!(_state(world), mask_filter)
    end
    return filter
end

@generated function _Filter_from_types(
    ::Type{W},
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

    exclusive = EX === Val{true}
    if exclusive && !isempty(without_types)
        throw(ArgumentError("cannot use 'exclusive' together with 'without'"))
    end

    CS = _world_storage_types(W)
    required_ids = Int[_component_index(CS, C) for C in required_types]
    with_ids = Int[_component_index(CS, C) for C in with_types]
    without_ids = Int[_component_index(CS, C) for C in without_types]
    non_exclude_ids = Int[_component_index(CS, C) for C in non_exclude_types]
    component_ids = Int[_component_index(CS, C) for C in comp_types]
    optional_ids = Int[_component_index(CS, C) for C in optional_types]
    rel_ids = Int[_component_index(CS, C) for C in rel_types]

    M = max(1, cld(fieldcount(CS), 64))
    K = fieldcount(relation_types)
    mask = _Mask{M}(required_ids..., with_ids...)
    exclude_mask = exclusive ? _Mask{M}(_Not(), non_exclude_ids...) : _Mask{M}(without_ids...)
    has_excluded = (length(without_ids) > 0) || exclusive
    component_mask = _Mask{M}(component_ids...)
    optional_mask = _Mask{M}(optional_ids...)
    register = REG === Val{true}

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
        filter_type = Filter{$W,$(QuoteNode(component_mask)),$exclusive,$(QuoteNode(optional_mask)),$M,$K}
        mask_filter = _MaskFilter{$M,$K}(
            $(mask),
            $(exclude_mask),
            $relations_expr,
            $register ? _IdCollection() : _empty_table_ids,
            Base.RefValue{UInt32}(UInt32(0)),
            $(has_excluded),
        )
        return filter_type, mask_filter
    end
end

"""
    unregister!(world::World, filter::Filter)

Un-registers a [Filter](@ref).
"""
function unregister!(world::World, filter::Filter)
    _unregister_filter!(_state(world), filter._filter)
end

function _matches(filter::F, archetype::_ArchetypeHot) where {F<:_MaskFilter}
    return _contains_all(archetype.mask, filter.mask) &&
           (!filter.has_excluded || !_contains_any(archetype.mask, filter.exclude_mask))
end

macro _each_matching_table(world_state, filter, archetypes, archetypes_hot, table, action)
    esc(quote
        for i in eachindex($(archetypes))
            archetype_hot = @inbounds $(archetypes_hot)[i]
            if !_matches($(filter), archetype_hot)
                continue
            end

            if !archetype_hot.has_relations
                table_id = archetype_hot.table
                $table = @inbounds $(world_state)._tables[Int(table_id)]
                if !isempty($table.entities)
                    $action
                end
                continue
            end

            archetype = @inbounds $(archetypes)[i]
            if isempty(archetype.tables)
                continue
            end

            tables = _get_tables($(world_state), archetype, $(filter).relations)
            for table_id in tables
                # TODO we can probably optimize here if exactly one relation in archetype and one queried.
                $table = @inbounds $(world_state)._tables[Int(table_id)]
                if !isempty($table.entities) && _matches($(world_state)._relations, $table, $(filter).relations)
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
        return _length_registered(_state(f._world), f._filter)
    else
        world_state = _state(f._world)
        arches, arches_hot = _get_archetypes(world_state, f)
        return _length(world_state, f._filter, arches, arches_hot)
    end
end

function _length(
    state::_WorldState,
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {M,K}
    count = 0
    @_each_matching_table(state, filter, archetypes, archetypes_hot, table, count += 1)
    return count
end

function _length_registered(state::_WorldState, filter::_MaskFilter{M,K}) where {M,K}
    count = 0
    @simd for table_id in filter.tables.ids
        table = @inbounds state._tables[table_id]
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
        return _count_entities_registered(_state(f._world), f._filter)
    else
        world_state = _state(f._world)
        arches, arches_hot = _get_archetypes(world_state, f)
        return _count_entities(world_state, f._filter, arches, arches_hot)
    end
end

function _count_entities(
    state::_WorldState,
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {M,K}
    count = 0
    @_each_matching_table(state, filter, archetypes, archetypes_hot, table, count += length(table.entities))
    return count
end

function _count_entities_registered(state::_WorldState, filter::_MaskFilter{M,K}) where {M,K}
    count = 0
    @simd for table_id in filter.tables.ids
        table = @inbounds state._tables[table_id]
        count += length(table.entities)
    end
    return count
end

function Base.show(io::IO, filter::Filter{W,CM,EX,OM,M,K}) where {W<:World,CM,EX,OM,M,K}
    world_types = fieldtypes(_world_component_types(W))
    component_ids = _active_bit_indices(CM)
    comp_types = tuple(DataType[_type_parameter(world_types[Int(id)]) for id in component_ids]...)

    mask_ids = _active_bit_indices(filter._filter.mask)
    mask_types = tuple(DataType[_type_parameter(world_types[Int(i)]) for i in mask_ids]...)

    required_types = intersect(mask_types, comp_types)
    optional_types = setdiff(comp_types, mask_types)
    with_types = setdiff(mask_types, comp_types)

    required_names = join(map(_format_type, required_types), ", ")
    optional_names = join(map(_format_type, optional_types), ", ")
    with_names = join(map(_format_type, with_types), ", ")
    is_exclusive = EX === true
    registered = _is_cached(filter._filter)

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
