
struct _Table
    entities::Entities
    relations::Vector{Pair{Int,Entity}}
    filters::_IdCollection
    id::UInt32
    archetype::UInt32
end

function _new_table(id::UInt32, archetype::UInt32)
    return _Table(Entities(0), Pair{Int,Entity}[], _IdCollection(), id, archetype)
end

function _new_table(id::UInt32, archetype::UInt32, cap::Int, relations::Vector{Pair{Int,Entity}})
    return _Table(Entities(cap), relations, _IdCollection(), id, archetype)
end

_has_relations(t::_Table) = !isempty(t.relations)

function _matches(indices::Vector{_ComponentRelations}, t::_Table, relations::Vector{Pair{Int,Entity}})
    if length(relations) == 0 || !_has_relations(t)
        return true
    end
    for (comp, target) in relations
        @inbounds trg = indices[comp].targets[t.id]
        if target._id != trg._id
            return false
        end
    end
    return true
end

function _matches_exact(indices::Vector{_ComponentRelations}, t::_Table, relations::Vector{Pair{Int,Entity}})
    # This check is done in _get_table_slow_path
    #if length(relations) < length(t.relations)
    #    throw(ArgumentError("relation targets must be fully specified"))
    #end
    for (comp, target) in relations
        # TODO: check for components not in the table
        # TODO: check for components that are no relations
        @inbounds trg = indices[comp].targets[t.id]
        if target._id != trg._id
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
