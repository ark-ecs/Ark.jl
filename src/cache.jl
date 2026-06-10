
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
    cache::_Cache{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
    tables::Vector{_Table},
    comp_relations::Vector{_ComponentRelations},
    filter::F,
) where {M,K,F<:_MaskFilter}
    if isempty(cache.free_indices)
        push!(cache.filters, filter)
        filter.id[] = UInt32(length(cache.filters))
    else
        index = pop!(cache.free_indices)
        cache.filters[index] = filter
        filter.id[] = index
    end

    for i in eachindex(archetypes)
        arch_hot = @inbounds archetypes_hot[i]
        if !_matches(filter, arch_hot)
            continue
        end

        if !arch_hot.has_relations
            _add_table!(filter, tables[arch_hot.table])
            continue
        end

        arch = @inbounds archetypes[i]
        tbl_ids = _get_tables(comp_relations, arch, filter.relations)
        for table_id in tbl_ids
            table = @inbounds tables[Int(table_id)]
            if _matches(comp_relations, table, filter.relations)
                _add_table!(filter, table)
            end
        end
    end
end

function _unregister_filter!(lock::_Lock, tables::Vector{_Table}, cache::_Cache, filter::F) where {F<:_MaskFilter}
    _check_locked(lock)

    if !_is_cached(filter)
        throw(InvalidStateException("filter is not registered to the cache", :filter_not_registered))
    end

    for table_id in filter.tables.ids
        table = tables[table_id]
        _remove_table_filter!(table, filter.id[])
    end

    if filter.id[] == length(cache.filters)
        pop!(cache.filters)
    else
        push!(cache.free_indices, filter.id[])
    end

    _clear!(filter.tables)
    filter.id[] = 0

    return nothing
end

function _add_table!(
    cache::_Cache,
    comp_relations::Vector{_ComponentRelations},
    archetype::_ArchetypeHot,
    table::_Table,
)
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
        if _matches(comp_relations, table, filter.relations)
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
