
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
    state = _state(filter._world)
    stores = _stores(filter._world)
    _check_locked(state)

    _lock(state._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds state._tables[table_id]
            if !isempty(table.entities)
                _shuffle_table!(rng, state, stores, table)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _shuffle(rng, state, stores, filter._filter, arches, arches_hot)
    end
    _unlock(state._lock)

    return filter
end

function _shuffle(
    rng::AbstractRNG,
    state::_WorldState{M,K},
    stores::_WorldStores,
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {M,K}
    @_each_matching_table(state, filter, archetypes, archetypes_hot, table, _shuffle_table!(rng, state, stores, table))
end

function _shuffle_table!(rng::AbstractRNG, state::_WorldState, stores::_WorldStores, table::_Table)
    len = length(table)
    archetype = state._archetypes[table.archetype]

    for i in len:-1:2
        j = @inline rand(rng, Random.Sampler(rng, Base.OneTo(i), Val(1)))
        _swap_rows!(state, stores, archetype, table, i, j)
    end
    return
end
