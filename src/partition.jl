
"""
    partition_entities!(filter::Filter; pred)

Partitions the entities matching the filter so that entities satisfying `pred`
come first within each table, while entities that do not satisfy `pred` are moved
to the end.
Partioning is performed per-table (archetype).
"""
function partition_entities!(filter::Filter; pred::P) where P
    _check_locked(filter._world)

    _lock(filter._world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds filter._world._tables[table_id]
            if !isempty(table.entities)
                _partition_table!(filter._world, table, pred)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _partition_entities!(filter._world, filter._filter, arches, arches_hot, pred)
    end
    _unlock(filter._world._lock)

    return filter
end

function _partition_entities!(
    world::World,
    filter::_MaskFilter{M,R},
    archetypes::Vector{<:_Archetype{M}},
    archetypes_hot::Vector{<:_ArchetypeHot{M}},
    pred::P,
) where {P,M,R}
    @_each_matching_table(
        world, filter, archetypes, archetypes_hot, table,
        _partition_table!(world, table, pred),
    )
end

function _partition_table!(world::World, table::_Table, pred::P) where P
    len = length(table)
    if len <= 1
        return
    end

    entities = table.entities._data
    archetype = world._archetypes[table.archetype]

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
            _swap_rows!(world, archetype, table, left, right)
            left += 1
            right -= 1
        end
    end

    return
end
