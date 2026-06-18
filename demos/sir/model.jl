
using Ark
using Random
using Parameters

include("../_common/resources.jl")
include("resources.jl")
include("components.jl")
include("utils.jl")

new_world(N) = World(S, I, R; initial_capacity=10^6)

function initialize_world!(world::World, N::Int, I0::Int, beta::Float64, c::Float64, r::Float64, dt, buffer=nothing)
    add_resource!(world, Tick(0))
    add_resource!(world, Time(0.0))
    add_resource!(world, Terminate(false))

    if isnothing(buffer)
        buffer = Buffer(world)
    end
    @eval global const BufferType = typeof($buffer)

    add_resource!(world, buffer)
    add_resource!(world, Params(N, I0, beta, c, r, dt))

    new_entities!(world, N - I0, (S(),))
    new_entities!(world, I0, (I(),))
    return world
end

function step_world!(world::World)
    params = get_resource(world, Params)
    Parameters.@unpack N, I0, beta, c, r, dt = params

    # Update world time
    get_resource(world, Tick).tick += 1
    get_resource(world, Time).time += dt

    # Calculate probabilities
    i_count = get_count(world, I)
    foi = beta * c * i_count / N
    prob_infection = rate_to_probability(foi, dt)
    prob_recovery = rate_to_probability(r, dt)

    buffer = get_resource(world, BufferType)
    Parameters.@unpack transitions, rands = buffer

    # S -> I Transition
    for (entities,) in Query(world, (), with=(S,))
        resize!(rands, length(entities))
        rand!(rands)
        @inbounds for k in eachindex(entities)
            if rands[k] <= prob_infection
                exchange_components!(world, transitions, entities[k]; add=(I(),), remove=(S,))
            end
        end
    end

    # I -> R Transition
    for (entities,) in Query(world, (), with=(I,))
        resize!(rands, length(entities))
        rand!(rands)
        @inbounds for k in eachindex(entities)
            if rands[k] <= prob_recovery
                exchange_components!(world, transitions, entities[k]; add=(R(),), remove=(I,))
            end
        end
    end

    # Apply Transitions
    apply!(world, transitions)

    return world
end
