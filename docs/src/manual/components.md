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
One or more components of an entity can be accessed via [get_components](@ref get_components(::World, ::Entity, ::Tuple)):

```@meta
DocTestSetup = quote
    using Ark
    using KernelAbstractions

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

Alternatively, you can get and check for components via indexing on an entity handle:

```jldoctest; output = false
we = world[entity]
pos = we[Position]
pos, vel = we[(Position, Velocity)]

has_pos = Position in we
has_pos_vel = (Position, Velocity) in we

# output

true
```

Similarly, the components of an entity can be overwritten by new values via [set_components!](@ref set_components!(::World, ::Entity, ::Tuple)) or by indexing:

```jldoctest; output = false
set_components!(world, entity, (Position(0, 0), Velocity(1,1)))
# or via handle
we = world[entity]
we[Position] = Position(0, 0)
we[(Position, Velocity)] = (Position(0, 0), Velocity(1, 1))

# output

(Position(0.0, 0.0), Velocity(1.0, 1.0))
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
For these columns, Ark offers storage types for both CPU anf GPU computing by default.

### CPU Storages

#### In-Memory Storages

- **Vector storage** stores components in a simple vector per column. This is the default.

- **[StructArray](@ref) storage** stores components in an SoA data structure similar to  
  [StructArrays](https://github.com/JuliaArrays/StructArrays.jl).  
  This allows access to field vectors in [queries](@ref Queries), enabling SIMD-accelerated,  
  vectorized operations and increased cache-friendliness if not all of the component's fields are used.
  [StructArray](@ref) storage has some limitations:  
  - Not allowed for mutable components.
  - Not allowed for components without fields, like labels and primitives.
  - ≈10-20% runtime overhead for component operations and entity creation.
  - Slower component access with [get_components](@ref get_components(::World, ::Entity, ::Tuple)) and [set_components!](@ref set_components!(::World, ::Entity, ::Tuple)).

### GPU Storages

#### Unified Memory Storages

- **[GPUVector](@ref) storage** stores components using unified memory for mixed CPU/GPU operations. [GPUVector](@ref) is compatible with CUDA.jl, Metal.jl, oneAPI.jl or OpenCL.jl, and with a device-less CPU backend. Mutable components are not allowed.

- **[GPUStructArray](@ref) storage** stores components in an SoA data structure similar to  
  [StructArrays](https://github.com/JuliaArrays/StructArrays.jl) using unified memory for mixed CPU/GPU operations. [GPUVector](@ref) is compatible with CUDA.jl, Metal.jl, oneAPI.jl or OpenCL.jl, and with a device-less CPU backend. The same limitations of [StructArray](@ref) storage apply.

## Storage Selection

The storage mode can be selected per component type by using the [Storage](@ref) wrapper during world construction.

```jldoctest; output = false
world = World(
    Position => Storage(Vector),
    Velocity => Storage(StructArray),
    Health,
)

# output

World(entities=0, comp_types=(Position, Velocity, Health))
```

The default is `Storage(Vector)` if no storage mode is specified:

```jldoctest; output = false
world = World(
    Position,
    Velocity => Storage(StructArray),
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

To use the [GPUVector](@ref) or the [GPUStructArray](@ref) storage, the back-end is specified
with a KernelAbstractions back-end instance (e.g. `CUDABackend()`, `MetalBackend()`,
`oneAPIBackend()` or `OpenCLBackend()`) depending on the GPU, as shown below:

```julia
using CUDA

world = World(
    Position => Storage(GPUVector, CUDABackend()),
    Velocity => Storage(GPUStructArray, CUDABackend()),
)
```

The additional `CPU()` back-end of KernelAbstractions.jl stores the components in plain `Vector`s and requires no
GPU package. It is useful to run and test GPU-shaped code on machines without a device:

```jldoctest; output = false
world = World(
    Position => Storage(GPUVector, CPU()),
    Velocity => Storage(GPUStructArray, CPU()),
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

On back-ends with more than one GPU, a specific device can be selected by passing a
device object, like `CuDevice(1)` for the second GPU of the system:

```julia
using CUDA

world = World(
    Position => Storage(GPUVector, CUDABackend(), CuDevice(1)),
    Velocity => Storage(GPUStructArray, CUDABackend(), CuDevice(1)),
)
```

All memory of these storages is allocated on the selected device, including
re-allocations during growth. Device selection is currently supported for the
`:CUDA`, `:Metal`, `:oneAPI` and `:OpenCL` back-ends. Kernels operating on the components
still have to be launched on the matching device (e.g. via `CUDA.device!`).

## [Synchronization with GPU Storages](@id gpu-storage-synchronization)

[GPUVector](@ref) and [GPUStructArray](@ref) store components in unified memory that is
directly visible to the host. Kernels launched on views of these storages, e.g. via
KernelAbstractions, execute *asynchronously*: launching a kernel only enqueues work,
it does not run to completion before the next host-side statement.

While any kernel that accesses GPU storages is still in flight, the same memory must
not be touched from the host. In an ECS this is easy to hit, because host access is not
limited to explicitly reading a query column. All of the following access GPU memory
immediately:

- Reading or writing components: indexing a storage or query column, `get_components`,
  `set_components!`.
- Structural operations: `new_entity!`, `remove_entity!`, `add_components!`,
  `remove_components!`, `reset!` of the world, and applying
  [command buffers](@ref command-buffer-api). These swap-remove, push or reallocate the
  underlying arrays.
- Growing a storage past its capacity, which reallocates and frees memory that an
  in-flight kernel may still be using.

The rule is therefore to **synchronize the backend before host code resumes working with
the world** - not only before reading results back. A typical frame looks like this:

```julia
backend = CUDABackend()
kernel = move_kernel(backend)

for (entities, positions, velocities) in Query(world, (Position, Velocity))
    kernel(positions, velocities; ndrange = length(entities))
end

# kernels are async: wait for them before *any* host access
KernelAbstractions.synchronize(backend)

# now safe: structural changes and host-side reads/writes
add_components!(world, entity, (Health(100),))
pos = get_components(world, entity, (Position,))[1]
```

Two remarks:

- Kernels that are launched consecutively on the same backend run in launch order, so
  dependent kernels do not need a `synchronize` in between. Only the boundary back to
  host code needs one.
- The `:CPU` back-end executes kernels synchronously, and unified-memory GPUs often
  appear to tolerate host access during flight. Code that violates this contract can
  therefore run correctly on `:CPU` - making CPU-only tests an unreliable way to catch
  such races.

!!! warning "Undefined behavior"
    Violating this contract is undefined behavior. In practice this ranges from stale or
    silently corrupted component values to kernels writing through memory that a
    reallocation has already freed. The `demos/gpu_hazards` directory in the repository
    contains minimal working examples of these failure modes.

## [Kernels over Multiple Tables](@id gpu-multi-table-kernels)

Query iteration launches one kernel per matching table. For many small tables this
scales poorly, and kernels that must read *all* matched entities (like n-body
all-pairs interactions) cannot be expressed with per-table launches at all.
[`FlatQuery`](@ref) creates a flat query over all matching tables that provides one
flat, linearly indexed view per component:

```julia
q = FlatQuery(world, Filter(world, (Position, Velocity)))

positions = q[Position]
velocities = q[Velocity]
move_kernel(backend)(positions, velocities, 0.5f0; ndrange = length(q))
KernelAbstractions.synchronize(backend)
```

For components stored in a [`GPUStructArray`](@ref), `q[Position]` returns a
`RaggedStructArray` whose field arrays are accessed by property or with
[`unpack`](@ref unpack(::RaggedStructArray)):

```julia
positions = q[Position]
px, py = unpack(positions)
field_kernel(backend)(px, py; ndrange = length(q))
```

The views span all matching tables in table order. Element access resolves the
owning table through the offsets, which costs one extra lookup per access
compared to a query column; writes scatter into the owning table's column.

The views can also be destructured in filter order, with the entity ids of all
matching tables last:

```julia
positions, velocities = q # component views, without entities
entities, positions, velocities = q # with entity ids
```

A flat query is a long-lived handle that re-derives its contents whenever it is
accessed, so it stays valid across structural changes. Views must be re-read from
the flat query after modifying the world - do not keep them across structural
changes:

```julia
new_entity!(world, (Position(0, 0), Velocity(0, 0)))
positions = q[Position] # re-read: picks up the new entity
```

Notes:

- Components must use GPU storages ([`GPUVector`](@ref) or [`GPUStructArray`](@ref),
  including the `CPU()` back-end). Optional components are not supported.
- Entity views are backed by host memory and are meant for host-side access;
  kernels should use only the component views.
- Relation targets can be used to select tables, but have no column views.
- Host-side indexing of views of real GPU memory is not supported; read components
  through the world or a query instead.

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
    Position => Storage(WrappedVector),
    Velocity => Storage(StructArray),
)

# output

World(entities=0, comp_types=(Position, Velocity))
```

All the methods in the example need to be defined, along with the empty constructor.
