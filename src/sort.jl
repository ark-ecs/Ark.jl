
"""
    sort_entities!(filter::Filter; kwargs...)

Sorts the entities matching the filter. The sorting is performed
per-table (archetype).

Accepts the same keyword arguments as `sort!`. The `by` and `lt`
functions operate on `Entity` values.

By default, the comparisons operates on the id of the entities
if no `by` function is specified. Also, the sorting algorithm
is `Base.Sort.QuickSort` since it is non-allocating.
"""
function sort_entities!(filter::Filter; alg=Base.Sort.QuickSort, kwargs...)
    state = _state(filter._world)
    stores = _stores(filter._world)
    _check_locked(state)

    _lock(state._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds state._tables[table_id]
            if !isempty(table.entities)
                _sort_table_entities!(state, stores, table; alg, kwargs...)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _sort_entities!(state, stores, filter._filter, arches, arches_hot; alg, kwargs...)
    end
    _unlock(state._lock)

    return filter
end

function _sort_entities!(
    state::_WorldState,
    stores::_WorldStores,
    filter::_MaskFilter,
    archetypes::Vector{<:_Archetype},
    archetypes_hot::Vector{<:_ArchetypeHot};
    alg::Base.Sort.Algorithm,
    kwargs...,
)
    @_each_matching_table(
        state,
        filter,
        archetypes,
        archetypes_hot,
        table,
        _sort_table_entities!(state, stores, table; alg, kwargs...)
    )

    return
end

function _sort_table_entities!(state::_WorldState, stores::_WorldStores, table::_Table; alg::Base.Sort.Algorithm, kwargs...)
    len = length(table)
    if len <= 1
        return
    end

    @inbounds begin
        sort!(table.entities._data; alg, kwargs...)

        archetype = state._archetypes[table.archetype]
        entities = table.entities

        # Components still have the old order
        for start in 1:len
            entity = entities[start]
            index = state._entities[entity._id]

            # table == 0 means this row's cycle was already processed
            if index.table == UInt32(0)
                continue
            end

            old_row = Int(index.row)

            if old_row != start
                for comp in archetype.components
                    _permute_component_cycle!(
                        stores,
                        comp,
                        table.id,
                        entities,
                        state._entities,
                        start,
                    )
                end
            end
        end

        # Restore the entity index to the final shuffled positions
        for row in 1:len
            entity = entities[row]
            state._entities[entity._id] = _EntityIndex(table.id, UInt32(row))
        end
    end

    return
end
