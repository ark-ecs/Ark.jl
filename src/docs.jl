# File to include as doctest setup:
# ```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl")))
# ...
# ```
struct Position
    x::Float64
    y::Float64
end

struct Velocity
    dx::Float64
    dy::Float64
end

struct Altitude
    z::Float64
end

struct Health
    h::Float64
end

struct ChildOf end

registry = EventRegistry()
const OnCollisionDetected = new_event_type!(registry, :OnCollisionDetected)

world = World(Position, Velocity, Altitude, Health, Relation{ChildOf})

parent = new_entity!(world, (Position(0, 0),))
parent2 = new_entity!(world, (Position(0, 0),))
entity = new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf() => parent))
