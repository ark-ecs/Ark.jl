
struct NParticles
    n::Int
end

struct TimeStep
    dt::Float32
end

struct WorldObservables
    pos::Observable{Vector{Point3f}}
    vel::Observable{Vector{Float64}}
    fps::Observable{String}
end

struct WorldFigure
    figure::Figure
end
