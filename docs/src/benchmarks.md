# Benchmarks

Several performance benchmarks for Ark.jl.

More to come soon...

## Ark vs. AoS

The figure below shows the classical Position/Velocity (movement system) benchmark,
comparing Ark with the Array of Structs approach.
Note that the data is from runs on the powerful GitHub CI machines.
These have way more cache then consumer machines, where the performance advantage
of Ark would be even more emphasized.

```@raw html
<img src="assets/images/bench_aos_light.svg" class="only-light" alt="Benchmark vs. AoS" />
<img src="assets/images/bench_aos_dark.svg" class="only-dark" alt="Benchmark vs. AoS" />
```
*Ark vs. AoS: Legend entries denote the size of entities in bytes and in the number of Float64 fields.*

## CPU vs. GPU Storage

Here, we illustrate the performance of a classical Position/Velocity example where the Position updates are offloaded to the GPU:

```julia
using Ark
using KernelAbstractions
using CUDA

struct Position
    x::Float32
    y::Float32
end

struct Velocity
    dx::Float32
    dy::Float32
end

@kernel function update_kernel!(positions, velocities)
    i = @index(Global)
    @inbounds begin
        pos = positions[i]
        vel = velocities[i]
        positions[i] = Position(pos.x + sin(vel.dx), pos.y + cos(vel.dy))
    end
end

function run_world(backend; n_entities=10^6, n_iterations=1000, use_gpu_storage=false)
    T = backend isa CUDABackend ? GPUVector{:CUDA} : Vector
    world = World(Position => Storage{T}, Velocity => Storage{T})

    for i in 1:n_entities
        new_entity!(world, (Position(Float32(i), Float32(i * 2)), Velocity(Float32(i), Float32(i))))
    end

    kernel = update_kernel!(backend, 256)
    for _ in 1:n_iterations
        for (entities, positions, velocities) in Query(world, (Position, Velocity))
            kernel(positions, velocities; ndrange=length(positions))
        end
    end

    return world
end
```

Performance-wise [GPUVector](@ref) performs best in this case on some local test hardware, as you can
see below:

```
julia> # AMD Ryzen 5 5600H
       @time run_world(CPU()) # 1 core
7.373623 seconds (7.53 k allocations: 141.863 MiB, 3.06% gc time)

julia> @time run_world(CPU()) # 6 cores
1.576263 seconds (32.53 k allocations: 143.663 MiB, 1.89% gc time)

julia> # NVIDIA GeForce GTX 1650
       @time run_world(CUDABackend())
0.325847 seconds (30.17 k allocations: 85.478 MiB, 0.36% gc time)
```
