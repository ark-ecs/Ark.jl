# Command buffer

The [CommandBuffer](@ref) allows deferring structural changes and applying them later in batch.
This is useful when you need to record changes during [query](@ref) iteration (when the [World](@ref) is locked),
or when you want to amortize the cost of structural changes across many operations.

## Creating a buffer

Create a [CommandBuffer](@ref) by providing the [World](@ref) and a tuple of operation specs:

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
end
```

```jldoctest
world = World(Position, Velocity, Health)
buf = CommandBuffer(world, (
    (new_entity!, (Position, Velocity)),
    (remove_entity!,),
    (add_components!, (Velocity,)),
    (remove_components!, (Velocity,)),
    (exchange_components!, (add=(Health,), remove=(Velocity,))),
));

# output

```

Each spec corresponds to one command type. The component types are captured at construction time
so the buffer's internal storage is specialized and allocation-free.

## Recording commands

All recording methods mirror the [World](@ref) API but take the buffer as an extra argument.

### Creating entities

Use [new_entity!](@ref) to stage entity creation. The entity ID is pre-allocated immediately
and returned, allowing it to be used in subsequent commands before [apply!](@ref) is called.

```jldoctest
world = World(Position, Velocity)
buf = CommandBuffer(world, ((new_entity!, (Position, Velocity)),))

e = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
apply!(world, buf)

# output

```

## Applying commands

Call [apply!](@ref) to execute all staged commands in FIFO order:

```jldoctest
world = World(Position, Velocity, Health)
buf = CommandBuffer(world, (
    (new_entity!, (Position, Velocity)),
    (add_components!, (Health,)),
))

e = new_entity!(world, buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)))
add_components!(world, buf, e, (Health(1.0),))

apply!(world, buf)

# output

```

After `apply!` the buffer is cleared and can be reused.
