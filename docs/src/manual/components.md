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

- **Vector storage** stores component objects in a simple vector per column. This is the default.

- **StructArray storage** stores components in an SoA data structure similar to  
  [StructArrays](https://github.com/JuliaArrays/StructArrays.jl).  
  This allows access to field vectors in [queries](@ref Queries), enabling SIMD-accelerated,  
  vectorized operations and increased cache-friendliness if not all of the component's fields are used.
  StructArray storage has some limitations:  
  - Not allowed for mutable components.
  - Not allowed for components without fields, like labels and primitives.
  - ≈10-20% runtime overhead for component operations and entity creation.
  - Slower component access with [get_components](@ref) and [set_components!](@ref).

The storage mode can be selected per component type by using `Storage{StructArray}` or `Storage{Vector}` during world construction.


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

### [A GPU storage implementation](@id gpu-storage)

One important application of custom storages is to support GPU storages. Here, we provide a possible, albeit not unique, 
implementation of a GPU storage fully compatible with the Ark API. It should work for all major backends (`CUDA.jl`, `AMDGPU.jl`, `Metal.jl` and `OneAPI.jl`) just by changing the `import` statement and the `GPUVecBackend` type accordingly.

```
using CUDA: @allowscalar
using Ark

const GPUVecBackend = CuVector

mutable struct GPUVector{T} <: AbstractVector{T}
    buffer::GPUVecBackend{T}
    len::Int
end
GPUVector{T}() where {T} = GPUVector(GPUVecBackend{T}(undef, 0), 0)

Base.size(s::GPUVector) = (s.len,)

function Base.getindex(s::GPUVector, i::Int)
    @boundscheck checkbounds(s, i)
    return @allowscalar s.buffer[i]
end

function Base.setindex!(s::GPUVector, v, i::Int)
    @boundscheck checkbounds(s, i)
    @allowscalar s.buffer[i] = v
    return s
end

function Base.resize!(s::GPUVector{T}, new_len::Integer) where {T}
    if new_len > length(s.buffer)
        new_cap = max(new_len, length(s.buffer) * 2)
        new_buffer = GPUVecBackend{T}(undef, new_cap)
        if s.len > 0
            copyto!(new_buffer, 1, s.buffer, 1, s.len)
        end
        
        s.buffer = new_buffer
    end
    s.len = new_len
    return s
end

function Base.empty!(s::GPUVector)
    s.len = 0
    return s
end

function Base.sizehint!(s::GPUVector{T}, n::Integer) where {T}
    if n > length(s.buffer)
        new_buffer = GPUVecBackend{T}(undef, n)
        if s.len > 0
            copyto!(new_buffer, 1, s.buffer, 1, s.len)
        end
        s.buffer = new_buffer
    end
    return s
end

function Base.push!(s::GPUVector{T}, v) where {T}
    resize!(s, s.len + 1)
    @inbounds s[s.len] = v
    return s
end

function Base.pop!(s::GPUVector)
    if s.len == 0
        throw(ArgumentError("array must be non-empty"))
    end
    val = s[s.len]
    s.len -= 1
    return val
end
```

Notice that a GPU storage like this will be more than an order of magnitude slower on all operations which mutates the world. However, transformations through queries which can be represented with GPU kernels will be performant. 
