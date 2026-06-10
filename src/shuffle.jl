
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
    _check_locked(filter._world._lock)

    _lock(filter._world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds filter._world._tables[table_id]
            if !isempty(table.entities)
                _shuffle_table!(rng, filter._world._entities, filter._world._storages, filter._world._archetypes, table)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _shuffle(rng, filter._world._entities, filter._world._storages, filter._world._archetypes, filter._filter, arches, arches_hot, filter._world._tables, filter._world._relations)
    end
    _unlock(filter._world._lock)

    return filter
end

function _shuffle(
    rng::AbstractRNG,
    entities::Vector{_EntityIndex},
    storages::CS,
    all_archetypes::Vector{_Archetype{M}},
    filter::_MaskFilter{M,K},
    filtered_archetypes::Vector{_Archetype{M}},
    filtered_archetypes_hot::Vector{_ArchetypeHot{M}},
    tables::Vector{_Table},
    comp_relations::Vector{_ComponentRelations},
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
                _shuffle_table!(rng, entities, storages, all_archetypes, table)
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
                _shuffle_table!(rng, entities, storages, all_archetypes, table)
            end
        end
    end
end

function _shuffle_table!(
    rng::AbstractRNG,
    entities::Vector{_EntityIndex},
    storages::CS,
    archetypes::Vector{_Archetype{M}},
    table::_Table,
) where {CS,M}
    len = length(table)
    archetype = archetypes[table.archetype]

    for i in len:-1:2
        j = @inline rand(rng, Random.Sampler(rng, Base.OneTo(i), Val(1)))
        _swap_rows!(entities, storages, archetype, table, i, j)
    end
    return
end


