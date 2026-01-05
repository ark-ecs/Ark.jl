# Components

Components contain the data associated to an [Entity](@ref Entities),
i.e. their properties or state variables.

## Component types

Components are distinguished by their type, and each entity can only have
one component of a certain type.

In Ark, any type can be used as a component.
However, it is highly recommended to use immutable types,
because mutable objects are usually allocated on the heap in Julia,
which defeats Ark's claim of high performance.
Mutable types are disallowed by default, but can be enabled when constructing a [World](@ref)
by the optional argument `allow_mutable` of the [world constructor](@ref World(::Type...; ::Bool)).

## Accessing components

Although the majority of the logic in an application that uses Ark will be performed in [Queries](@ref),
it may be necessary to access components for a particular entity.
One or more components of an entity can be accessed via [get_components](@ref):

```@meta
DocTestSetup = quote
    using Ark

    struct Position
        x::Float64
        y::Float64
    end
    struct Velocity
        dx::Float64
        dy::Float64
    end
    struct Health
        value::Float64
    end

    world = World(Position, Velocity, Health)
    entity = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
end
```

```jldoctest; output = false
(pos, vel) = get_components(world, entity, (Position, Velocity))

# output

(Position(0.0, 0.0), Velocity(0.0, 0.0))
```

Similarly, the components of an entity can be overwritten by new values via [set_components!](@ref),
which is particularly useful for immutable components (which are the default):

```jldoctest; output = false
set_components!(world, entity, (Position(0, 0), Velocity(1,1)))

# output

```

## Adding and removing components

A feature that makes ECS particularly flexible and powerful is the ability to
add components to and remove them from entities at runtime.
This works similar to component access and can be done via [add_components!](@ref) and [remove_components!](@ref):

```jldoctest; output = false
entity = new_entity!(world, ())

add_components!(world, entity, (Position(0, 0), Velocity(1,1)))
remove_components!(world, entity, (Velocity,))

# output

```

Note that adding an already existing component or removing a missing one results in an error.

Also note that it is more efficient to add/remove multiple components at once instead of one by one.
To allow for efficient exchange of components (i.e. add some and remove others in the same operation),
[exchange_components!](@ref) can be used:


```jldoctest; output = false
entity = new_entity!(world, (Position(0, 0), Velocity(1,1)))

exchange_components!(world, entity; 
    add    = (Health(100),),
    remove = (Position, Velocity),
)

# output

```

For manipulating entities in batches, [add_components!](@ref), [remove_components!](@ref) and [exchange_components!](@ref)
come with versions that take a filter instead of a single entity as argument.
See chapter [Batch operations](@ref) for details.

## [Default component storages](@id component-storages)

Components are stored in [archetypes](@ref Architecture),
with the values for each component type stored in a separate array-like column.
For these columns, Ark offers two storage types by default:

- **Vector storage** stores components in a simple vector per column. This is the default.

- **[StructArray](@ref) storage** stores components in an SoA data structure similar to  
  [StructArrays](https://github.com/JuliaArrays/StructArrays.jl).  
  This allows access to field vectors in [queries](@ref Queries), enabling SIMD-accelerated,  
  vectorized operations and increased cache-friendliness if not all of the component's fields are used.
  [StructArray](@ref) storage has some limitations:  
  - Not allowed for mutable components.
  - Not allowed for components without fields, like labels and primitives.
  - ≈10-20% runtime overhead for component operations and entity creation.
  - Slower component access with [get_components](@ref) and [set_components!](@ref).

- **[GPUSyncVector](@ref) storage** stores components in hybrid vector implementation that manages data synchronization between a CPU host vector and a GPU buffer. [GPUSyncVector](@ref) is compatible with all major backends (CUDA.jl, AMDGPU.jl, Metal.jl and oneAPI.jl). As [StructArray](@ref) storage, mutable components are not allowed.

The storage mode can be selected per component type by using the [Storage](@ref) wrapper during world construction.

```jldoctest; output = false
world = World(
    Position => Storage{Vector},
    Velocity => Storage{StructArray},
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

The default is `Storage{Vector}` if no storage mode is specified:

```jldoctest; output = false
world = World(
    Position,
    Velocity => Storage{StructArray},
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

To use the [GPUSyncVector](@ref) storage, also the GPU backend vector must be specified, which can be imported from one of the major backends (CUDA.jl, AMDGPU.jl, Metal.jl or oneAPI.jl) depending on the GPU. To illustrate its usage and performance we provide a classical Position/Velocity example where the Position updates are offloaded to the GPU:

```
using CUDA
using Ark

struct Position
    x::Float32
    y::Float32
end

struct Velocity
    dx::Float32
    dy::Float32
end

function update!(positions, velocities)
    index = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    stride = blockDim().x * gridDim().x
    @inbounds for i in index:stride:length(positions)
        pos = positions[i]
        vel = velocities[i]
        positions[i] = Position(pos.x + sin(vel.dx), pos.y + cos(vel.dy))
    end
    return
end

function run_world_gpu()
    world = World(
        Position => Storage{GPUSyncVector{CuVector}},
        Velocity => Storage{GPUSyncVector{CuVector}},
    )
    for i in 1:10^6
        new_entity!(world, (Position(i, i * 2), Velocity(i, i)))
    end

    for i in 1:1000
        for (entities, positions, velocities) in Query(world, (Position, Velocity))
            gpu_pos = gpuview(positions)
            gpu_vel = gpuview(velocities)
            blocks = cld(length(gpu_pos), 256)
            @cuda threads=256 blocks=blocks update!(gpu_pos, gpu_vel)
        end
    end
    return world
end

function run_world_cpu()
    world = World(Position, Velocity)
    for i in 1:10^6
        entity = new_entity!(world, (Position(i, i * 2), Velocity(i, i)))
    end
    for i in 1:1000
        for (entities, positions, velocities) in Query(world, (Position, Velocity))
            Threads.@threads for i in eachindex(entities)
                @inbounds pos = positions[i]
                @inbounds vel = velocities[i]
                @inbounds positions[i] = Position(pos.x + sin(vel.dx), pos.y + cos(vel.dy))
            end
        end
    end
    return world
end
```

Performance-wise the hybrid `GPUSyncVector` performs best on some local test hardware as you can
see below:

```
julia> # AMD Ryzen 5 5600H
       @time run_world_cpu() # 1 core
7.373623 seconds (7.53 k allocations: 141.863 MiB, 3.06% gc time)

julia> @time run_world_cpu() # 6 cores
1.576263 seconds (32.53 k allocations: 143.663 MiB, 1.89% gc time)

julia> # NVIDIA GeForce GTX 1650
       @time run_world_gpu()
0.240809 seconds (19.61 k allocations: 141.952 MiB, 42.24% gc time)
```

## [User-defined component storages](@id new-component-storages)

New storage modes can be created by the user. The new storage must be a one-indexed subtype of `AbstractVector` and must implement its required interface along with some optional methods. A complete example of a custom type is this one:

```jldoctest; output = false
struct WrappedVector{C} <: AbstractVector{C}
    v::Vector{C}
end
WrappedVector{C}() where C = WrappedVector{C}(Vector{C}())

Base.size(w::WrappedVector) = size(w.v)
Base.getindex(w::WrappedVector, i::Integer) = getindex(w.v, i)
Base.setindex!(w::WrappedVector, v, i::Integer) = setindex!(w.v, v, i)
Base.empty!(w::WrappedVector) = empty!(w.v)
Base.resize!(w::WrappedVector, i::Integer) = resize!(w.v, i)
Base.sizehint!(w::WrappedVector, i::Integer) = sizehint!(w.v, i)
Base.pop!(w::WrappedVector) = pop!(w.v)

world = World(
    Position => Storage{WrappedVector},
    Velocity => Storage{StructArray},
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

All the methods in the example need to be defined, along with the empty constructor.

