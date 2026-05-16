
mutable struct _LastTable{M}
    mask::_Mask{M}
    id::UInt32
end

_RelationId(::Val{M}) where {M} =
    64M <= typemax(UInt8) ? UInt8 : 64M <= typemax(UInt16) ? UInt16 : UInt32

function _empty_relations(::Val{M}) where {M}
    R = _RelationId(Val(M))
    return Vector{Pair{R,Entity}}()
end

function _relation(::Val{M}, id::Integer, target::Entity) where {M}
    R = _RelationId(Val(M))
    return R(id) => target
end

struct _Table{R}
    entities::Entities
    relations::Vector{Pair{R,Entity}}
    filters::_IdCollection
    id::UInt32
    archetype::UInt32
end

function _new_table(::Val{M}, id::UInt32, archetype::UInt32) where {M}
    R = _RelationId(Val(M))
    return _Table{R}(Entities(0), _empty_relations(Val(M)), _IdCollection(), id, archetype)
end

function _new_table(::Val{M}, id::UInt32, archetype::UInt32, cap::Int, relations::Vector{Pair{R,Entity}}) where {M,R}
    return _Table{R}(Entities(cap), relations, _IdCollection(), id, archetype)
end

_has_relations(t::_Table{R}) where {R} = !isempty(t.relations)

function _matches(indices::Vector{_ComponentRelations}, t::_Table{TR}, relations::Vector{Pair{R,Entity}}) where {TR,R<:Integer}
    if length(relations) == 0 || !_has_relations(t)
        return true
    end
    for (comp, target) in relations
        @inbounds trg = indices[Int(comp)].targets[t.id]
        if target != trg
            return false
        end
    end
    return true
end

function _matches_exact(indices::Vector{_ComponentRelations}, t::_Table{TR}, relations::Vector{Pair{R,Entity}}) where {TR,R<:Integer}
    # This check is done in _get_table_slow_path
    #if length(relations) < length(t.relations)
    #    throw(ArgumentError("relation targets must be fully specified"))
    #end
    for (comp, target) in relations
        # TODO: check for components not in the table
        # TODO: check for components that are no relations
        @inbounds trg = indices[Int(comp)].targets[t.id]
        if target != trg
            return false
        end
    end
    return true
end

function _add_entity!(t::_Table{R}, entity::Entity)::Int where {R}
    push!(t.entities._data, entity)
    return length(t.entities)
end

Base.length(t::_Table{R}) where {R} = Base.length(t.entities)
Base.isempty(t::_Table{R}) where {R} = Base.isempty(t.entities)
Base.resize!(t::_Table{R}, length::Int) where {R} = Base.resize!(t.entities._data, length)
Base.empty!(t::_Table{R}) where {R} = Base.empty!(t.entities._data)
