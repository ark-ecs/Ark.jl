# The World

A [World](@ref world-api) is the central data store for any application that uses Ark.jl.
It manages [Entities](@ref), [Components](@ref) and [Resources](@ref),
and all these are always tied to a World.

Most applications will have exactly one world, but multiple worlds can exist at the same time.

## World creation

When creating a new world, all [Component types](@ref Components) that can exist in it must be specified.

```jldoctest world; output = false
using Ark

struct Position
    x::Float64
    y::Float64
end

struct Velocity
    dx::Float64
    dy::Float64
end

world = World(Position, Velocity)

# output

World(entities=0, comp_types=(Position, Velocity))
```

This may seem unusual, but it allows Ark to leverage Julia's compile-time programming
features for the best performance.

## Initial capacity

The [World constructor](@ref World(::Type...)) takes an option keyword argument `initial_capacity`
to allocate memory for the given number of [entities](@ref Entities) in each [archetype](@ref Architecture).
This is useful to speed up entity creations by avoiding repeated allocations.

```jldoctest world; output = false
world = World(Position, Velocity; initial_capacity=1024)

# output

World(entities=0, comp_types=(Position, Velocity))
```

## World modes

The keyword argument `mode` selects how much code Ark generates per component type. It can either be `:specialized` or `:boxed`.

Queries and iteration are statically typed in both modes.

### Boxed storage

By default Ark resolves the component of a structural operation by generating one branch per component type, each holding a copy of the operation specialized for that component, and holds the component storages in a tuple. That is what makes structural operations fast, but both grow with the number of component types a world declares, and so does the time spent compiling them.

The boxed mode removes both. Structural operations are routed through type-erased calls, each compiled only when it is first used, and the storages are kept in an untyped container whose types are carried as values rather than as static arguments. No generated code is left that depends on the number of component types in the operations. The effect grows with the number of component types.

Stay on `:specialized` unless compile time is a problem, and measure before committing to `:boxed`.

## World reset

Ark's primary goal is to empower high-performance simulation models.
In this domain, it is common to run large numbers of simulations, whether to explore model stochasticity,
perform calibration, or for optimization purposes.

To maximize efficiency, Ark provides a [reset!](@ref) function that resets a simulation world for subsequent reuse.
This significantly accelerates model initialization by reusing already allocated memory and avoiding costly reallocation.

```jldoctest world; output = false
reset!(world)

# output

```

## World functionality

You will see that almost all methods in Ark's API take a World as their first argument.
These methods are explained in the following chapters.
