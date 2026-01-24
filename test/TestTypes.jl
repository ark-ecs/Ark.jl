
struct A
    x::Float64
end

struct B
    x::Float64
end

struct C <: Relationship end

struct Position
    x::Float64
    y::Float64
end

Base.copy(pos::Position) = Position(pos.x, pos.y)

struct Velocity
    dx::Float64
    dy::Float64
end

struct Altitude
    alt::Float64
end

struct Health
    health::Float64
end

struct Dummy end

struct LabelComponent end

struct CompN{N} end

mutable struct MutableComponent
    dummy::Int64
end

struct NoIsBits
    v::Vector{Int}
end

mutable struct MutableNoIsBits
    v::Vector{MutableComponent}
end

struct ChildOf <: Relationship end
struct ChildOf2 <: Relationship end
struct ChildOf3 <: Relationship end

mutable struct Tick
    time::Int
end
