
"""
    partition_entities!(filter::Filter; pred)

Partitions the entities matching the filter so that entities satisfying `pred`
come first within each table, while entities that do not satisfy `pred` are moved
to the end.
Partioning is performed per-table (archetype).
"""
function partition_entities!(filter::Filter; pred::P) where P
    _check_locked(filter._world._lock)

    _lock(filter._world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds filter._world._tables[table_id]
            if !isempty(table.entities)
                _partition_table!(filter._world._entities, filter._world._storages, filter._world._archetypes, table, pred)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _partition_entities!(filter._world._entities, filter._world._storages, filter._world._archetypes, filter._filter, arches, arches_hot, filter._world._tables, filter._world._relations, pred)
    end
    _unlock(filter._world._lock)

    return filter
end

function _partition_entities!(
    entities::Vector{_EntityIndex},
    storages::CS,
    all_archetypes::Vector{_Archetype{M}},
    filter::_MaskFilter{M,K},
    filtered_archetypes::Vector{_Archetype{M}},
    filtered_archetypes_hot::Vector{_ArchetypeHot{M}},
    tables::Vector{_Table},
    comp_relations::Vector{_ComponentRelations},
    pred::P,
) where {M,K,CS,P}
    for i in eachindex(filtered_archetypes)
        archetype_hot = @inbounds filtered_archetypes_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end

        if !archetype_hot.has_relations
            table_id = archetype_hot.table
            table = @inbounds tables[Int(table_id)]
            if !isempty(table.entities)
                _partition_table!(entities, storages, all_archetypes, table, pred)
            end
            continue
        end

        archetype = @inbounds filtered_archetypes[i]
        if isempty(archetype.tables)
            continue
        end

        tbl_ids = _get_tables(comp_relations, archetype, filter.relations)
        for table_id in tbl_ids
            table = @inbounds tables[Int(table_id)]
            if !isempty(table.entities) && _matches(comp_relations, table, filter.relations)
                _partition_table!(entities, storages, all_archetypes, table, pred)
            end
        end
    end
end

function _partition_table!(
    entity_index::Vector{_EntityIndex},
    storages::CS,
    archetypes::Vector{_Archetype{M}},
    table::_Table,
    pred::P,
) where {CS,M,P}
    len = length(table)
    if len <= 1
        return
    end

    tbl_entities = table.entities._data
    archetype = archetypes[table.archetype]

    left = 1
    right = len

    @inbounds while left <= right
        while left <= right && pred(tbl_entities[left])
            left += 1
        end

        while left <= right && !pred(tbl_entities[right])
            right -= 1
        end

        if left < right
            _swap_rows!(entity_index, storages, archetype, table, left, right)
            left += 1
            right -= 1
        end
    end

    return
end


