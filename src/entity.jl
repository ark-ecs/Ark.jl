"""
    Entity

[Entity](@ref Entities) identifier.

Entities can be constructed using a [World](@ref) via [new_entity!](@ref) and [new_entities!](@ref).

Entities can be safely stored in [components](@ref Components) and [resources](@ref Resources).
"""
struct Entity
    _id::UInt32
    _gen::UInt32

    global _Entity(id::UInt32, gen::UInt32) = new(id, gen)
end

"""
    is_zero(entity::Entity)::Bool

Returns whether an [Entity](@ref) is the reserved [zero_entity](@ref).
"""
function is_zero(entity::Entity)::Bool
    return entity._id == 1
end

"""
    Base.isless(a::Entity, b::Entity)

Test whether the id of `a` is smaller than the id of `b`.
"""
Base.isless(a::Entity, b::Entity) = isless(a._id, b._id)

function _new_entity(id::UInt32, gen::UInt32)
    _Entity(id, gen)
end

function _new_entity(id::Int, gen::Int)
    _Entity(UInt32(id), UInt32(gen))
end

function Base.show(io::IO, entity::Entity)
    print(io, "Entity($(Int(entity._id)), $(Int(entity._gen)))")
end

# One record per entity id, combining location (table, row), liveness
# generation and flags in a single cache line. `_WorldState._entities` and
# `_EntityPool.entities` alias the same vector of these records.
# For dead (recycled) entities, `row` holds the id of the next entity in the
# pool's free list.
struct _EntityIndex
    table::UInt32
    row::UInt32
    gen::UInt32
    flags::UInt32
end

# The entity is the target of at least one relationship.
const _TARGET_FLAG = UInt32(1)

_is_target(index::_EntityIndex)::Bool = index.flags & _TARGET_FLAG != UInt32(0)

# Update location only, preserving generation and flags.
@inline function _set_location!(entities::Vector{_EntityIndex}, id::UInt32, table::UInt32, row::UInt32)
    @inbounds index = entities[id]
    @inbounds entities[id] = _EntityIndex(table, row, index.gen, index.flags)
    return nothing
end

@inline function _set_target_flag!(entities::Vector{_EntityIndex}, id::UInt32)
    @inbounds index = entities[id]
    @inbounds entities[id] = _EntityIndex(index.table, index.row, index.gen, index.flags | _TARGET_FLAG)
    return nothing
end

"""
    Entities

Archetype column for entities. Can be iterated and indexed like a Vector, but is read-only.

Used in [query iteration](@ref Queries) and [batch operations](@ref "Batch operations") callbacks.
"""
struct Entities <: AbstractVector{Entity}
    _data::Vector{Entity}
    function Entities(cap::Int)
        vec = Vector{Entity}()
        if cap > 0
            sizehint!(vec, cap)
        end
        new(vec)
    end
end

function _new_entities_column()
    Entities(1024)
end

Base.@propagate_inbounds function Base.getindex(c::Entities, i::Integer)
    getindex(c._data, i)
end
Base.length(c::Entities) = length(c._data)
Base.eachindex(c::Entities) = eachindex(c._data)
Base.iterate(c::Entities) = iterate(c._data)
Base.iterate(c::Entities, state) = iterate(c._data, state)
Base.IndexStyle(::Type{Entities}) = IndexLinear()
Base.size(c::Entities) = (length(c),)
Base.firstindex(c::Entities) = firstindex(c._data)
Base.lastindex(c::Entities) = lastindex(c._data)

function Base.show(io::IO, e::Entities)
    if length(e) < 12
        elems = join(e, ", ")
        print(io, "Entities[$elems]")
    else
        first = join(e[1:5], ", ")
        last = join(e[(end-4):end], ", ")
        print(io, "Entities[$first, …, $last]")
    end
end
