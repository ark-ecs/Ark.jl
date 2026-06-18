struct GrassGrid
    capacity::Array{Float64,2}
    grass::Observable{Array{Float64,2}}
end

struct WorldSize
    width::Int
    height::Int
    scale::Int
end

mutable struct SimulationSpeed
    speed::Int
end

struct GrazerMortalityCommands{B<:CommandBuffer}
    commands::B
end

GrazerMortalityCommands(world::World) =
    GrazerMortalityCommands(CommandBuffer(world, ((remove_entity!,),)))

struct GrazerDecisionCommands{B<:CommandBuffer}
    commands::B
end

GrazerDecisionCommands(world::World) = GrazerDecisionCommands(CommandBuffer(world, (
    (exchange_components!, (add=(Grazing,), remove=(Moving,))),
    (exchange_components!, (add=(Moving,), remove=(Grazing,))),
)))

struct Window
    scene::GLMakie.Scene
    screen::GLMakie.Screen
end

struct Grazers
    positions::Observable{Vector{Point2f}}
    rotations::Observable{Vector{Float64}}
end

struct PlotData
    max_angle::Observable{Vector{Float64}}
    reverse_prob::Observable{Vector{Float64}}

    move_thresh::Observable{Vector{Float64}}
    graze_thresh::Observable{Vector{Float64}}

    num_offspring::Observable{Vector{Float64}}
    energy_share::Observable{Vector{Float64}}
end

PlotData() = PlotData(
    Observable(Float64[]),
    Observable(Float64[]),
    Observable(Float64[]),
    Observable(Float64[]),
    Observable(Float64[]),
    Observable(Float64[]),
)
