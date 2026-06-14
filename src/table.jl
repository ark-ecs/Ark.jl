
mutable struct _LastTable{M}
    mask::_Mask{M}
    id::UInt32
end

struct _Table
    entities::Entities
    relations::Vector{Pair{Int32,Entity}}
    filters::Base.RefValue{_IdCollection}
    id::UInt32
    archetype::Int
    local_table::Int
end

function _new_table(id::UInt32, archetype::Int, local_table::Int, cap::Int, relations::Vector{Pair{Int32,Entity}})
    return _Table(Entities(cap), relations, Ref(_empty_id_collection), id, archetype, local_table)
end

_has_relations(t::_Table) = !isempty(t.relations)

function _add_table_filters!(table::_Table)
    filters = table.filters[]
    if filters === _empty_id_collection
        filters = _IdCollection()
        table.filters[] = filters
    end
    return filters
end

function _remove_table_filter!(table::_Table, filter_id::UInt32)
    filters = table.filters[]
    @check filters !== _empty_id_collection
    removed = _remove_id!(filters, filter_id)
    return removed
end

struct _FilterRelations{K}
    len::Int
    ids::NTuple{K,Int32}
    targets::NTuple{K,Entity}
end

Base.length(relations::_FilterRelations) = relations.len
Base.isempty(relations::_FilterRelations) = relations.len == 0

Base.@propagate_inbounds function Base.getindex(relations::_FilterRelations, i::Integer)
    return relations.ids[i] => relations.targets[i]
end

Base.iterate(relations::_FilterRelations) = iterate(relations, 1)

function Base.iterate(relations::_FilterRelations, state::Int)
    state > relations.len && return nothing
    rel = @inbounds relations[state]
    return rel, state + 1
end

function _matches(indices::Vector{_ComponentRelations}, t::_Table, relations::_FilterRelations)
    if length(relations) == 0 || !_has_relations(t)
        return true
    end
    for (comp, target) in relations
        @inbounds trg = indices[comp%Int].targets[t.id]
        if target != trg
            return false
        end
    end
    return true
end

function _matches_exact(indices::Vector{_ComponentRelations}, t::_Table, relations::Vector{Pair{Int32,Entity}})
    # This check is done in _get_table_slow_path
    #if length(relations) < length(t.relations)
    #    throw(ArgumentError("relation targets must be fully specified"))
    #end
    for (comp, target) in relations
        # TODO: check for components not in the table
        # TODO: check for components that are no relations
        @inbounds trg = indices[comp%Int].targets[t.id]
        if target != trg
            return false
        end
    end
    return true
end

function _add_entity!(t::_Table, entity::Entity)::Int
    push!(t.entities._data, entity)
    return length(t.entities)
end

Base.length(t::_Table) = Base.length(t.entities)
Base.isempty(t::_Table) = Base.isempty(t.entities)
Base.resize!(t::_Table, length::Int) = Base.resize!(t.entities._data, length)
Base.empty!(t::_Table) = Base.empty!(t.entities._data)
