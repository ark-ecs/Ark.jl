
"""
    shuffle_entities!(world::World, filter::Filter)
    shuffle_entities!(rng::AbstractRNG, world::World, filter::Filter)

Shuffles the entities matching the filter.
The shuffling is performed per-table (archetype).
"""
function shuffle_entities!(world::World, filter::F) where {F<:Filter}
    shuffle_entities!(Random.default_rng(), world, filter)
end

function shuffle_entities!(rng::AbstractRNG, world::World, filter::F) where {F<:Filter}
    _check_filter_world(world, filter)
    _check_locked(world)

    _lock(world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds world._tables[table_id]
            if !isempty(table.entities)
                _shuffle_table!(rng, world, table)
            end
        end
    else
        arches, arches_hot = _get_archetypes(world, filter)
        _shuffle(rng, world, filter._filter, arches, arches_hot)
    end
    _unlock(world._lock)

    return filter
end

function _shuffle(
    rng::AbstractRNG,
    world::World{M,K},
    filter::_MaskFilter{M,K},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {M,K}
    @_each_matching_table(world, filter, archetypes, archetypes_hot, table, _shuffle_table!(rng, world, table))
end

function _shuffle_table!(rng::AbstractRNG, world::World, table::_Table)
    len = length(table)
    archetype = world._archetypes[table.archetype]

    for i in len:-1:2
        j = @inline rand(rng, Random.Sampler(rng, Base.OneTo(i), Val(1)))
        _swap_rows!(world, archetype, table, i, j)
    end
    return
end
