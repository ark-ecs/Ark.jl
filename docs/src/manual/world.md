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

The keyword argument `mode` selects how much code Ark generates per component type. The three
modes form a ladder, each erasing strictly more than the one before it:

| `mode` | generated per component type |
|:--|:--|
| `:monomorphic` (default) | a specialized copy of every structural operation |
| `:erased` | the selection of a storage only, as a single trivial branch |
| `:boxed` | nothing at all |

Queries and iteration are statically typed in every mode.

### Erased dispatch

By default Ark resolves the component of a structural operation by generating one branch per
component type, each holding a copy of the operation specialized for that component. This is
what makes structural operations fast, but the size of the generated code grows with the
number of component types a world declares, and so does the time spent compiling it.

For worlds with many component types, `mode=:erased` routes those operations through
type-erased calls instead. The generated code then no longer depends on the number of
component types, and each per-component call is compiled only when it is first used.

```jldoctest world; output = false
world = World(Position, Velocity; mode=:erased)

# output

World(entities=0, comp_types=(Position, Velocity))
```

The effect grows with the number of component types: `:monomorphic` compiles
super-linearly, while the erased dispatch stays close to linear.

```@raw html
<img src="../assets/images/bench_erased_compile_light.svg" class="only-light" alt="Compile time: default vs erased dispatch" />
<img src="../assets/images/bench_erased_compile_dark.svg" class="only-dark" alt="Compile time: default vs erased dispatch" />
```
*First-call compile time of the structural operations as the number of component types grows.
Below a few dozen component types the erased dispatch is slightly slower to compile; above
that its advantage widens quickly. World construction is measured separately, in the
[boxed storage](@ref Boxed-storage) section, since it is what the next step addresses.*

This is a trade-off, not a free improvement:

  - Compilation cost of structural operations grows super-linearly with the number of
    component types under `:monomorphic`, but stays close to linear when erased. The mode
    pays off for worlds with a few dozen component types and above.
  - Structural operations on individual entities (adding and removing components, creating
    and removing entities, copying entities, shuffling) become roughly 2x slower.
  - Queries, batch operations and sorting are unaffected, as they operate per archetype
    column rather than per entity.

Stay on `:monomorphic` unless compile time is a problem, and measure both before committing
to another mode.

### Boxed storage

`:erased` addresses the code that *operates* on the component storages. The storages
themselves are still held in a tuple, and a tuple can only be built by code that names every
element, so world construction keeps one specialized call per component type in a single
method. That method is the most expensive thing Ark compiles for a large schema.

`mode=:boxed` keeps the storages in a `Vector{Any}` instead. The types are then carried as
values rather than as static arguments, so the world creates and registers its storages in a
runtime loop, and the size of the world constructor no longer depends on the number of
component types.

```jldoctest world; output = false
world = World(Position, Velocity; mode=:boxed)

# output

World(entities=0, comp_types=(Position, Velocity))
```

`:boxed` builds on `:erased` rather than being an independent knob: it keeps the erased
dispatch and additionally removes the last piece of generated code that grows with the
schema, which is the switch that maps a component id to its storage. That leaves no
per-component generated code anywhere.

The effect is on world construction, which the erased dispatch leaves untouched: it grows
super-linearly with the number of component types when the storages are held in a tuple, and
close to linearly when they are boxed.

```@raw html
<img src="../assets/images/bench_boxed_ctor_light.svg" class="only-light" alt="Compile time of world construction" />
<img src="../assets/images/bench_boxed_ctor_dark.svg" class="only-dark" alt="Compile time of world construction" />
```
*First-call compile time of world construction as the number of component types grows.*

It also keeps the peak memory of the compiling process nearly flat, since the world
constructor is by far the largest method Ark compiles for a big schema.

This is a trade-off, not a free improvement:

  - Compiling the world constructor gets much cheaper, but the per-component storage
    constructors do not disappear, they are merely compiled separately. The saving is in the
    super-linear term, so it grows with the number of component types and is small below a
    few hundred of them.
  - Reading a storage costs a type check, since its type has to be restored from the
    `Vector{Any}`. This is a tag comparison and a load, and it does not allocate: a storage is
    boxed once at world creation and never replaced. Queries are unaffected, as they resolve
    their storages once when the query is created.
  - Structural operations compile slightly more code per call site than in a tuple world.

Stay on `:erased` or `:monomorphic` unless world-construction compile time is a problem, and
measure before committing to `:boxed`.

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
