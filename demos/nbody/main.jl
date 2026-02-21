
using Ark
using GLMakie
using KernelAbstractions
using Random

include("resources.jl")
include("components.jl")
include("sys/nbody_physics.jl")
include("sys/nbody_plot.jl")

const IS_CI = "CI" in keys(ENV)

function nbody_simulation(n, dt, backend)
    T = (backend isa CUDABackend) ? GPUStructArray{:CUDA} : StructArray
    world = World(
        Position => Storage{T},
        Velocity => Storage{T},
        Mass => Storage{T},
    )

    add_resource!(world, TimeStep(dt))
    add_resource!(world, NParticles(n))

    initialize!(NBodyPhysics(), world)
    initialize!(NBodyPlot(), world)

    fig = get_resource(world, WorldFigure).figure
    display(fig)

    GC.gc()

    k = 0
    while isopen(fig.scene)
        t0 = time_ns()

        update!(NBodyPhysics(), world, backend)
        update!(NBodyPlot(), world)

        t1 = time_ns()

        fps_obs = get_resource(world, WorldObservables).fps
        fps_obs[] = "FPS: $(round(1e9 / (t1 - t0), digits=1))"
        sleep(max(0, 1/60 - (t1-t0) / 1e9))
        yield()

        k += 1
        IS_CI && k == 2 && return
    end
end

function main(backend)
    n, dt = 10000, 0.01f0
    nbody_simulation(n, dt, backend)
end

main(CPU())

# For better performance, use a GPU backend like so:
#
# using CUDA
# main(CUDABackend())
