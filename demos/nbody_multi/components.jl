
struct Position
    x::Float32
    y::Float32
    z::Float32
end

struct Velocity
    x::Float32
    y::Float32
    z::Float32
end

struct Mass
    val::Float32
end

# Marker component for the black hole. The extra tag places it in its own
# table, which the FlatQuery views pick up automatically once it has spawned.
struct BlackHole end
