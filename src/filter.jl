
"""
    Filter

A filter for components. See function
[Filter](@ref Filter(::World,::Tuple;::Tuple,::Tuple,::Tuple,::Bool)) for details.
See also [Query](@ref).
"""
struct Filter{W<:World,TS<:Tuple,EX,OPT,REG,M}
    _filter::_MaskFilter{M}
    _world::W
end

"""
    Filter(
        world::World,
        comp_types::Tuple;
        with::Tuple=(),
        without::Tuple=(),
        optional::Tuple=(),
        exclusive::Bool=false,
        relations::Tuple=(),
        register::Bool=false,
    )

Creates a filter.
Filters are similar to [queries](@ref Query), but can't be iterated directly.
They are a re-usable way to define query filtering criteria, and can be registered for faster, cached queries.
Further, filters are used in [batch operations](@ref "Batch operations").

See the user manual chapter on [Queries](@ref) for more details and examples.

# Arguments

  - `world`: The `World` instance to filter.
  - `comp_types::Tuple`: Components the filter filters for.
  - `with::Tuple`: Additional components the entities must have.
  - `without::Tuple`: Components the entities must not have.
  - `optional::Tuple`: Additional components that are optional in the filter.
  - `exclusive::Bool`: Makes the filter exclusive in base and `with` components, can't be combined with `without`.
  - `relations::Tuple`: Relationship component type => target entity pairs. These relation components must be in the filter's components or `with`.
"""
Base.@constprop :aggressive function Filter(
    world::World,
    comp_types::Tuple;
    with::Tuple=(),
    without::Tuple=(),
    optional::Tuple=(),
    exclusive::Bool=false,
    register::Bool=false,
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return _Filter_from_types(world,
        ntuple(i -> Val(comp_types[i]), length(comp_types)),
        ntuple(i -> Val(with[i]), length(with)),
        ntuple(i -> Val(without[i]), length(without)),
        ntuple(i -> Val(optional[i]), length(optional)),
        Val(exclusive),
        Val(register),
        rel_types, targets,
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
    world_storage_modes = W.parameters[3].parameters

    required_types = _to_types(CT)
    with_types = _to_types(WT)
    without_types = _to_types(WO)
    optional_types = _to_types(OT)
    rel_types = _to_types(TR)

    # check for duplicates
    all_comps = vcat(required_types, with_types, without_types, optional_types)
    _check_no_duplicates(all_comps)

    _check_no_duplicates(rel_types)
    _check_relations(rel_types)

    comp_types = union(required_types, optional_types)
    non_exclude_types = union(comp_types, with_types)

    _check_is_subset(rel_types, union(required_types, with_types))

    if EX === Val{true} && !isempty(without_types)
        throw(ArgumentError("cannot use 'exclusive' together with 'without'"))
    end

    CS = W.parameters[1]
    required_ids = map(C -> _component_id(CS, C), required_types)
    with_ids = map(C -> _component_id(CS, C), with_types)
    without_ids = map(C -> _component_id(CS, C), without_types)
    non_exclude_ids = map(C -> _component_id(CS, C), non_exclude_types)
    rel_ids = map(C -> _component_id(CS, C), rel_types)

    M = max(1, cld(length(CS.parameters), 64))
    mask = _Mask{M}(required_ids..., with_ids...)
    exclude_mask = EX === Val{true} ? _Mask{M}(_Not(), non_exclude_ids...) : _Mask{M}(without_ids...)
    has_excluded = (length(without_ids) > 0) || (EX === Val{true})
    register = REG === Val{true}

    comp_tuple_type = Expr(:curly, :Tuple, comp_types...)

    optional_flag_type_elts = [
        (T in optional_types) ? :(Val{true}) : :(Val{false})
        for T in comp_types
    ]
    optional_flags_type = Expr(:curly, :Tuple, optional_flag_type_elts...)

    return quote
        relations = if length(targets) > 0
            # TODO: can/should we use an ntuple instead?
            rel = Vector{Pair{Int,Entity}}()
            for (c, e) in zip($rel_ids, targets)
                push!(rel, c => e)
            end
            rel
        else
            _empty_relations
        end
        filter = Filter{$W,$comp_tuple_type,$EX,$optional_flags_type,$REG,$M}(
            _MaskFilter{$M}(
                $(mask),
                $(exclude_mask),
                relations,
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
function unregister!(filter::F) where {F<:Filter}
    _unregister_filter!(filter._world, filter._filter)
end

function _matches(filter::F, archetype::_ArchetypeHot) where {F<:_MaskFilter}
    return _contains_all(archetype.mask, filter.mask) &&
           (!filter.has_excluded || !_contains_any(archetype.mask, filter.exclude_mask))
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
    filter::_MaskFilter{M},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M}
    count = 0
    for i in eachindex(archetypes)
        archetype_hot = @inbounds archetypes_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end

        if !archetype_hot.has_relations
            table = @inbounds world._tables[Int(archetype_hot.table)]
            if isempty(table.entities)
                continue
            end
            count += 1
            continue
        end

        archetype = @inbounds archetypes[i]
        if isempty(archetype.tables)
            continue
        end

        tables = _get_tables(world, archetype, filter.relations)
        for table_id in tables
            # TODO we can probably optimize here if exactly one relation in archetype and one queried.
            table = @inbounds world._tables[Int(table_id)]
            if !isempty(table.entities) && _matches(world._relations, table, filter.relations)
                count += 1
            end
        end
    end
    count
end

function _length_registered(world::W, filter::_MaskFilter{M}) where {W<:World,M}
    count = 0
    for table_id in filter.tables.ids
        table = @inbounds world._tables[table_id]
        if !isempty(table.entities)
            count += 1
        end
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
    filter::_MaskFilter{M},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M}
    count = 0
    for i in eachindex(archetypes)
        archetype_hot = @inbounds archetypes_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end

        if !archetype_hot.has_relations
            table = @inbounds world._tables[Int(archetype_hot.table)]
            count += length(table.entities)
            continue
        end

        archetype = @inbounds archetypes[i]
        if isempty(archetype.tables)
            continue
        end

        tables = _get_tables(world, archetype, filter.relations)
        for table_id in tables
            # TODO we can probably optimize here if exactly one relation in archetype and one queried.
            table = @inbounds world._tables[Int(table_id)]
            if !isempty(table.entities) && _matches(world._relations, table, filter.relations)
                count += length(table.entities)
            end
        end
    end
    count
end

function _count_entities_registered(world::W, filter::_MaskFilter{M}) where {W<:World,M}
    count = 0
    for table_id in filter.tables.ids
        table = @inbounds world._tables[table_id]
        count += length(table.entities)
    end
    return count
end

function Base.show(io::IO, filter::Filter{W,CT,EX,OPT,REG,M}) where {W<:World,CT<:Tuple,EX<:Val,OPT,REG<:Val,M}
    world_types = W.parameters[2].parameters
    comp_types = CT.parameters

    mask_ids = _active_bit_indices(filter._filter.mask)
    mask_types = tuple(map(i -> world_types[Int(i)].parameters[1], mask_ids)...)

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
    if registered
        push!(kw_parts, "registered=true")
    end

    if isempty(kw_parts)
        print(io, "Filter(($required_names))")
    else
        print(io, "Filter(($required_names); ", join(kw_parts, ", "), ")")
    end
end

"""
    shuffle_entities!(filter::Filter)
    shuffle_entities!(rng::AbstractRNG, filter::Filter)

Shuffles the entities matching the filter.
The shuffling is performed per-table (archetype).
"""
function shuffle_entities!(filter::F) where {F<:Filter}
    shuffle_entities!(Random.default_rng(), filter)
end

function shuffle_entities!(rng::AbstractRNG, filter::F) where {F<:Filter}
    _check_locked(filter._world)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds filter._world._tables[table_id]
            if !isempty(table.entities)
                _shuffle_table!(rng, filter._world, table)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _shuffle(rng, filter._world, filter._filter, arches, arches_hot)
    end
    return filter
end

function _shuffle(
    rng::AbstractRNG,
    world::W,
    filter::_MaskFilter{M},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M}
    for i in eachindex(archetypes)
        archetype_hot = @inbounds archetypes_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end

        if !archetype_hot.has_relations
            table = @inbounds world._tables[Int(archetype_hot.table)]
            if isempty(table.entities)
                continue
            end
            _shuffle_table!(rng, world, table)
            continue
        end

        archetype = @inbounds archetypes[i]
        if isempty(archetype.tables)
            continue
        end

        tables = _get_tables(world, archetype, filter.relations)
        for table_id in tables
            table = @inbounds world._tables[Int(table_id)]
            if !isempty(table.entities) && _matches(world._relations, table, filter.relations)
                _shuffle_table!(rng, world, table)
            end
        end
    end
end
