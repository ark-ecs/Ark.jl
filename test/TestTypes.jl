
struct A
    x::Float64
end

struct B
    x::Float64
end

struct C end

struct Position
    x::Float64
    y::Float64
end

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

struct NoIsBits2
    v::Vector{Vector{Int}}
end

mutable struct MutableNoIsBits
    v::Vector{MutableComponent}
end

struct ChildOf end
struct ChildOf2 end
struct ChildOf3 end

mutable struct Tick
    time::Int
end

struct DiskRelation
    weight::Int
end

struct Position_Mod
    x::Float64
    y::Float64
end

function Base.getproperty(value::Position_Mod, name::Symbol)
    return nothing
end
