
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
    world = filter._world
    _check_locked(world._lock)

    _lock(world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds world._tables[table_id]
            if !isempty(table.entities)
                _sort_table_entities!(world._archetypes, world._entities, world._storages, table; alg, kwargs...)
            end
        end
    else
        arches, arches_hot = _get_archetypes(world, filter)
        _sort_entities!(world._archetypes, world._entities, world._storages, filter._filter, arches, arches_hot, world._tables, world._relations; alg, kwargs...)
    end
    _unlock(world._lock)

    return filter
end

function _sort_entities!(
    all_archetypes::Vector{_Archetype{M}},
    world_entities::Vector{_EntityIndex},
    storages::CS,
    filter::_MaskFilter{M,K},
    filtered_archetypes::Vector{_Archetype{M}},
    filtered_archetypes_hot::Vector{_ArchetypeHot{M}},
    tables::Vector{_Table},
    comp_relations::Vector{_ComponentRelations};
    alg::Base.Sort.Algorithm,
    kwargs...,
) where {M,K,CS}
    for i in eachindex(filtered_archetypes)
        archetype_hot = @inbounds filtered_archetypes_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end

        if !archetype_hot.has_relations
            table_id = archetype_hot.table
            table = @inbounds tables[Int(table_id)]
            if !isempty(table.entities)
                _sort_table_entities!(all_archetypes, world_entities, storages, table; alg, kwargs...)
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
                _sort_table_entities!(all_archetypes, world_entities, storages, table; alg, kwargs...)
            end
        end
    end

    return
end

function _sort_table_entities!(
    archetypes::Vector{_Archetype{M}},
    world_entities::Vector{_EntityIndex},
    storages::CS,
    table::_Table;
    alg::Base.Sort.Algorithm,
    kwargs...,
) where {M,CS}
    len = length(table)
    if len <= 1
        return
    end

    @inbounds begin
        sort!(table.entities._data; alg, kwargs...)

        archetype = archetypes[table.archetype]
        table_entities = table.entities

        # Components still have the old order
        for start in 1:len
            entity = table_entities[start]
            index = world_entities[entity._id]

            # table == 0 means this row's cycle was already processed
            if index.table == UInt32(0)
                continue
            end

            old_row = Int(index.row)

            if old_row != start
                for comp in archetype.components
                    _permute_component_cycle!(
                        storages,
                        comp,
                        table.id,
                        table_entities,
                        world_entities,
                        start,
                    )
                end
            end
        end

        # Restore the entity index to the final shuffled positions
        for row in 1:len
            entity = table_entities[row]
            world_entities[entity._id] = _EntityIndex(table.id, UInt32(row))
        end
    end

    return
end
