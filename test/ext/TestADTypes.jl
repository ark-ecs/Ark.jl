struct Position{T<:Number}
    x::T
    y::T
end

struct Velocity{T<:Number}
    dx::T
    dy::T
end

struct ChildOf <: Relationship end
