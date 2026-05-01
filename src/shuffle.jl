
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
    _check_locked(filter._world)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds filter._world._tables[table_id]
            if !isempty(table.entities)
                _shuffle_table!(rng, filter._world, table)
            end
        end
    else
        arches, arches_hot = _get_archetypes(filter._world, filter)
        _shuffle(rng, filter._world, filter._filter, arches, arches_hot)
    end
    return filter
end

function _shuffle(
    rng::AbstractRNG,
    world::W,
    filter::_MaskFilter{M},
    archetypes::Vector{_Archetype{M}},
    archetypes_hot::Vector{_ArchetypeHot{M}},
) where {W<:World,M}
    @_each_matching_table(world, filter, archetypes, archetypes_hot, table, _shuffle_table!(rng, world, table))
end

#function _shuffle_table!(rng::AbstractRNG, world::World, table::_Table)
#    len = length(table)
#    archetype = world._archetypes[table.archetype]

#    for i in len:-1:2
#        j = @inline rand(rng, Random.Sampler(rng, Base.OneTo(i), Val(1)))
#        _swap_rows!(world, archetype, table, i, j)
#    end
#    return
#end

function _shuffle_table!(rng::AbstractRNG, world::World, table::_Table)
    len = length(table)
    len <= 1 && return nothing

    @inbounds begin
        archetype = world._archetypes[table.archetype]
        entities = table.entities

        # shuffle only entity rows
        for i in len:-1:2
            j = @inline rand(rng, Random.Sampler(rng, Base.OneTo(i), Val(1)))

            if i != j
                entities._data[i], entities._data[j] = entities._data[j], entities._data[i]
            end
        end

        # world._entities still contains old rows
        for comp in archetype.components
            _permute_component_data!(world, comp, table.id, entities)
        end

        # restore entity indices to the final shuffled positions.
        for row in 1:len
            entity = entities[row]
            world._entities[entity._id] = _EntityIndex(table.id, UInt32(row))
        end
    end

    return nothing
end
