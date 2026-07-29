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

The keyword argument `mode` selects how much code Ark generates per component type.

| `mode` | generated per component type |
|:--|:--|
| `:specialized` (default) | a specialized copy of every structural operation |
| `:boxed` | nothing at all |

Queries and iteration are statically typed in both modes.

### Boxed storage

By default Ark resolves the component of a structural operation by generating one branch per
component type, each holding a copy of the operation specialized for that component, and
holds the component storages in a tuple. That is what makes structural operations fast, but
both grow with the number of component types a world declares, and so does the time spent
compiling them. A tuple can only be built by code that names every element, so world
construction also keeps one specialized call per component type in a single method - the
most expensive thing Ark compiles for a large schema.

`mode=:boxed` removes both. Structural operations are routed through type-erased calls, each
compiled only when it is first used, and the storages are kept in a `Memory{Any}` whose types
are carried as values rather than as static arguments, so the world creates and registers its
storages in a runtime loop. No generated code is left that depends on the number of component
types, in the operations or in the constructor.

```jldoctest world; output = false
world = World(Position, Velocity; mode=:boxed)

# output

World(entities=0, comp_types=(Position, Velocity))
```

The effect grows with the number of component types: `:specialized` compiles super-linearly,
both in the structural operations and in world construction, while `:boxed` stays close to
linear in each.

```@raw html
<img src="../assets/images/bench_boxed_compile_light.svg" class="only-light" alt="Compile time of the structural operations" />
<img src="../assets/images/bench_boxed_compile_dark.svg" class="only-dark" alt="Compile time of the structural operations" />
```
*First-call compile time of the structural operations as the number of component types grows.
Below a few dozen component types `:boxed` is slightly slower to compile; above that its
advantage widens quickly.*

```@raw html
<img src="../assets/images/bench_boxed_ctor_light.svg" class="only-light" alt="Compile time of world construction" />
<img src="../assets/images/bench_boxed_ctor_dark.svg" class="only-dark" alt="Compile time of world construction" />
```
*First-call compile time of world construction as the number of component types grows.*

It also keeps the peak memory of the compiling process nearly flat, since the world
constructor is by far the largest method Ark compiles for a big schema.

This is a trade-off, not a free improvement:

  - Compilation of both the structural operations and the world constructor gets much
    cheaper, but the per-component work does not disappear, it is merely compiled separately
    and on demand. The saving is in the super-linear term, so it grows with the number of
    component types and is small below a few dozen of them.
  - Structural operations on individual entities (adding and removing components, creating
    and removing entities, copying entities, shuffling) become roughly 2x slower, because each
    one dispatches through a wrapper per component instead of an inlined branch.
  - Reading a storage costs a type check, since its type has to be restored from the
    `Memory{Any}`. This is a tag comparison and a load, and it does not allocate: a storage is
    boxed once at world creation and never replaced. Reading several components of one entity
    at a time - `world[entity][(Position, Velocity)]` - is where this is most visible.
  - Queries, batch operations and sorting are unaffected, as they resolve their storages once
    per table and then operate per archetype column rather than per entity.

Stay on `:specialized` unless compile time is a problem, and measure before committing to
`:boxed`.

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
