
struct Position
    x::Float64
    y::Float64
end

struct Velocity
    dx::Float64
    dy::Float64
end

struct ChildOf end

struct CompA
    x::Float64
    y::Float64
end

struct CompB
    x::Float64
    y::Float64
end

struct CompC
    x::Float64
    y::Float64
end

struct CompN{N}
    x::Float64
    y::Float64
end

mutable struct Tick
    time::Int
end
