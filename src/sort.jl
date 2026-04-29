
struct _SortableEntities{W<:World,M} <: AbstractVector{Entity}
    world::W
    archetype::_Archetype{M}
    table::_Table
end

Base.IndexStyle(::Type{<:_SortableEntities}) = IndexLinear()
Base.eltype(::Type{<:_SortableEntities}) = Entity
Base.size(v::_SortableEntities) = (length(v),)
Base.length(v::_SortableEntities) = length(v.table.entities)
Base.firstindex(v::_SortableEntities) = 1
Base.lastindex(v::_SortableEntities) = length(v)

@inline function Base.getindex(v::_SortableEntities, i::Int)
    return @inbounds v.table.entities._data[i]
end

@inline function Base.setindex!(v::_SortableEntities, entity::Entity, i::Int)
    world, table, archetype = v.world, v.table, v.archetype

    @inbounds idx = world._entities[entity._id]
    j = Int(idx.row)

    @check idx.table == table.id

    if i != j
        _swap_rows!(world, archetype, table, i, j)
    end

    return entity
end

"""
    sort_entities!(filter::Filter; kwargs...)

Sorts the entities matching the filter. The sorting is performed
per-table (archetype).

Accepts the same keyword arguments as `sort!`. The `by` and `lt`
functions operate on `Entity` values.

By default, the comparisons operates on the id of the entities
if no `by` function is specified.
"""
function sort_entities!(filter::Filter; kwargs...)
    world = filter._world
    _check_locked(world)

    _lock(world._lock)
    if _is_cached(filter._filter)
        for table_id in filter._filter.tables.ids
            table = @inbounds world._tables[table_id]
            if !isempty(table.entities)
                _sort_table_entities!(world, table; kwargs...)
            end
        end
    else
        arches, arches_hot = _get_archetypes(world, filter)
        _sort_entities!(world, filter._filter, arches, arches_hot; kwargs...)
    end
    _unlock(world._lock)

    return filter
end

function _sort_entities!(
    world::World,
    filter::_MaskFilter,
    archetypes::Vector{<:_Archetype},
    archetypes_hot::Vector{<:_ArchetypeHot};
    kwargs...,
)
    @_each_matching_table(
        world,
        filter,
        archetypes,
        archetypes_hot,
        table,
        _sort_table_entities!(world, table; kwargs...)
    )

    return
end

function _sort_table_entities!(world::World, table::_Table; kwargs...)
    if length(table) <= 1
        return
    end

    @inbounds archetype = world._archetypes[table.archetype]
    sortable = _SortableEntities(world, archetype, table)

    sort!(sortable; kwargs...)

    return
end
