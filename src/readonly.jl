
"""
    Const(T)

Marks component `T` as read-only in a [`Query`](@ref) or [`Filter`](@ref).

Queries and filters still match entities by the underlying component type `T`,
but the returned component column is a read-only view.

# Example

```julia
for (_, positions, velocities) in Query(world, (Const(Position), Velocity))
    pos = positions[1]            # allowed
    velocities[1] = velocities[1] # allowed
    positions[1] = pos            # errors
end
```
"""
struct Const{T}
    function Const(::Type{T}) where T
        if !isbitstype(T)
            throw(ArgumentError("A component can be marked constant only if immutable."))
        end
        return new{T}()
    end
end

function _unwrap_ext_const_type(::Const{T}) where {T}
    return T
end

function _unwrap_ext_const_type(::Type{T}) where {T}
    return T
end

function _unwrap_const_type(::Type{Const{T}}) where {T}
    return T
end

function _unwrap_const_type(::Type{T}) where {T}
    return T
end

function _is_const_type(::Type{Const{T}}) where {T}
    return true
end

function _is_const_type(::Type{T}) where {T}
    return false
end

struct ReadOnly{T,V<:AbstractVector{T}} <: AbstractVector{T}
    a::V
end

_readonly_type(::Type{V}) where {T,V<:AbstractVector{T}} = ReadOnly{T,V}

Base.IndexStyle(::Type{<:ReadOnly{T,V}}) where {T,V} = IndexStyle(V)

Base.size(C::ReadOnly) = size(getfield(C, :a))

Base.axes(C::ReadOnly) = axes(getfield(C, :a))

Base.@propagate_inbounds Base.getindex(A::ReadOnly, i::Integer) = getfield(A, :a)[i]

function Base.getproperty(A::ReadOnly, name::Symbol)
    return ReadOnly(getproperty(getfield(A, :a), name))
end
