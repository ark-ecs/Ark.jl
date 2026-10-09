
struct NParticles
    n::Int
end

struct TimeStep
    dt::Float32
end

# Two black holes start `distance` units away from the cloud center, mirrored
# to the left and right, each with the given mass.
struct BlackHoleConfig
    mass::Float32
    distance::Float32
end
