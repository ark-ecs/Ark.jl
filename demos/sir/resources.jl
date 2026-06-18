
struct Buffer{B<:CommandBuffer}
    transitions::B
    rands::Vector{Float64}
    ents::Vector{Entity}
end

function Buffer(world::World, rands=Float64[], ents=Entity[])
    transitions = CommandBuffer(world, (
        (exchange_components!, (add=(I,), remove=(S,))),
        (exchange_components!, (add=(R,), remove=(I,))),
    ))

    # hint to max capacity for more fluid simulations
    sizehint!(rands, 10^6)
    sizehint!(ents, 10^6)
    return Buffer(transitions, rands, ents)
end

mutable struct Params
    N::Int
    I0::Int
    beta::Float64
    c::Float64
    r::Float64
    dt::Float64
end
