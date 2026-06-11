
"""
    partition_entities!(filter::Filter; pred)

Partitions the entities matching the filter so that entities satisfying `pred`
come first within each table, while entities that do not satisfy `pred` are moved
to the end.
Partioning is performed per-table (archetype).
"""
function partition_entities!(filter::Filter; pred::P) where P
    world_state = _state(filter._world)
    stores = _stores(filter._world)
    _check_locked(world_state)

    _lock(world_state._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds world_state._tables[table_id]
            if !isempty(table.entities)
                _partition_table!(world_state, stores, table, pred)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _partition_entities!(world_state, stores, filter._filter, arches, arches_hot, pred)
    end
    _unlock(world_state._lock)

    return filter
end

function _partition_entities!(
    state::_WorldState,
    stores::_WorldStores,
    filter::_MaskFilter,
    archetypes::Vector{<:_Archetype},
    archetypes_hot::Vector{<:_ArchetypeHot},
    pred::P,
) where P
    @_each_matching_table(
        state, filter, archetypes, archetypes_hot, table,
        _partition_table!(state, stores, table, pred),
    )
end

function _partition_table!(state::_WorldState, stores::_WorldStores, table::_Table, pred::P) where P
    len = length(table)
    if len <= 1
        return
    end

    entities = table.entities._data
    archetype = state._archetypes[table.archetype]

    left = 1
    right = len

    @inbounds while left <= right
        while left <= right && pred(entities[left])
            left += 1
        end

        while left <= right && !pred(entities[right])
            right -= 1
        end

        if left < right
            _swap_rows!(state, stores, archetype, table, left, right)
            left += 1
            right -= 1
        end
    end

    return
end
