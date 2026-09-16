
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

# Relation component: bodies are grouped into clusters, and each cluster is its
# own table. All clusters still belong to the same archetype.
struct Cluster end
