
struct Buffer{B<:CommandBuffer}
    transitions::B
    rands::Vector{Float64}
    ents::Vector{Entity}
end

const TRANSITION_COMMAND_SPECS = (
    ExchangeComponentsCommand(add=I, remove=S),
    ExchangeComponentsCommand(add=R, remove=I),
)

function Buffer(world::World, rands=Float64[], ents=Entity[])
    transitions = CommandBuffer(world, TRANSITION_COMMAND_SPECS)

    # hint to max capacity for more fluid simulations
    sizehint!(rands, 10^6)
    sizehint!(ents, 10^6)
    return Buffer(transitions, rands, ents)
end

const BufferType = Buffer{typeof(CommandBuffer(World(S, I, R), TRANSITION_COMMAND_SPECS))}

mutable struct Params
    N::Int
    I0::Int
    beta::Float64
    c::Float64
    r::Float64
    dt::Float64
end
