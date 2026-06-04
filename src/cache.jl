
struct _MaskFilter{M,K}
    mask::_Mask{M}
    exclude_mask::_Mask{M}
    relations::_FilterRelations{K}
    tables::_IdCollection
    id::Base.RefValue{UInt32}
    has_excluded::Bool
end

_is_cached(f::_MaskFilter) = f.id[] > 0

function _add_table!(filter::F, table::_Table) where {F<:_MaskFilter}
    _add_id!(filter.tables, table.id)
    table_filters = _add_table_filters!(table)
    _add_id!(table_filters, filter.id[])
end

struct _Cache{M,K}
    filters::Vector{_MaskFilter{M,K}}
    free_indices::Vector{UInt32}
end

_Cache{M,K}() where {M,K} = _Cache{M,K}(Vector{_MaskFilter{M,K}}(), Vector{UInt32}())

function _register_filter!(
    world::W,
    filter::F,
) where {W<:_AbstractWorld,F<:_MaskFilter}
    # TODO: re-enable this check in case re-registration is allowed.
    #if _is_cached(filter)
    #    throw(InvalidStateException("filter is already registered to the cache", :filter_registered))
    #end

    if isempty(world._cache.free_indices)
        push!(world._cache.filters, filter)
        filter.id[] = UInt32(length(world._cache.filters))
    else
        index = pop!(world._cache.free_indices)
        world._cache.filters[index] = filter
        filter.id[] = index
    end

    for i in eachindex(world._archetypes)
        arch_hot = @inbounds world._archetypes_hot[i]
        if !_matches(filter, arch_hot)
            continue
        end

        if !arch_hot.has_relations
            _add_table!(filter, world._tables[arch_hot.table])
            continue
        end

        arch = @inbounds world._archetypes[i]
        tables = _get_tables(world, arch, filter.relations)
        for table_id in tables
            table = @inbounds world._tables[Int(table_id)]
            if _matches(world._relations, table, filter.relations)
                _add_table!(filter, table)
            end
        end
    end
end

function _unregister_filter!(world::W, filter::F) where {W<:_AbstractWorld,F<:_MaskFilter}
    _check_locked(world)

    if !_is_cached(filter)
        throw(InvalidStateException("filter is not registered to the cache", :filter_not_registered))
    end

    for table_id in filter.tables.ids
        table = world._tables[table_id]
        _remove_table_filter!(table, filter.id[])
    end

    if filter.id[] == length(world._cache.filters)
        pop!(world._cache.filters)
    else
        push!(world._cache.free_indices, filter.id[])
    end

    _clear!(filter.tables)
    filter.id[] = 0

    return nothing
end

function _add_table!(
    cache::_Cache,
    world::W,
    archetype::_ArchetypeHot,
    table::_Table,
) where {W<:_AbstractWorld}
    for filter in cache.filters
        if !_is_cached(filter)
            continue
        end
        if !_matches(filter, archetype)
            continue
        end
        if !archetype.has_relations
            _add_table!(filter, table)
            continue
        end
        if _matches(world._relations, table, filter.relations)
            _add_table!(filter, table)
        end
    end
end

function _remove_table!(cache::_Cache, table::_Table)
    table_filters = table.filters[]
    if table_filters === _empty_id_collection
        return nothing
    end

    for filter_id in table_filters.ids
        filter = cache.filters[filter_id]
        _remove_id!(filter.tables, table.id)
    end
    _clear!(table.filters[])
end

function _reset!(cache::_Cache)
    for filter in cache.filters
        _clear!(filter.tables)
        filter.id[] = UInt32(0)
    end

    empty!(cache.filters)
    empty!(cache.free_indices)
end
