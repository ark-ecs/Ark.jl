# Command buffer

The [CommandBuffer](@ref) allows deferring structural changes and applying them later in batch.
This is useful when you need to record changes during [Query](@ref) iteration (when the [World](@ref) is locked),
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
world = World(Position, Velocity, Health);
buf = CommandBuffer(world, (
    NewEntityCommand((Position, Velocity)),
    RemoveEntityCommand(),
    AddComponentsCommand((Velocity,)),
    RemoveComponentsCommand((Velocity,)),
    ExchangeComponentsCommand(add=(Health,), remove=(Velocity,)),
));

# output

CommandBuffer{World{Ark._WorldStorage{Tuple{Ark._ComponentStorage{Position, Vector{Position}}, Ark._ComponentStorage{Velocity, Vector{Velocity}}, Ark._ComponentStorage{Health, Vector{Health}}}, (0x0000000000000000,)}, Ark._WorldState{1, 0}}, Union{AddComponentsCommand{Tuple{Velocity}}, ExchangeComponentsCommand{Tuple{Health}, Tuple{Velocity}}, NewEntityCommand{Tuple{Position, Velocity}}, RemoveComponentsCommand{Tuple{Velocity}}, RemoveEntityCommand}}(World(entities=0, comp_types=(Position, Velocity, Health)), Union{AddComponentsCommand{Tuple{Velocity}}, ExchangeComponentsCommand{Tuple{Health}, Tuple{Velocity}}, NewEntityCommand{Tuple{Position, Velocity}}, RemoveComponentsCommand{Tuple{Velocity}}, RemoveEntityCommand}[])
```

Each spec corresponds to one command type. The component types are captured at construction time
so the buffer's internal storage is specialized and allocation-free.
Arbitrary command types can also be included in the specs and recorded with [`record!`](@ref).

## Recording commands

All recording methods mirror the [World](@ref) API but take the buffer as an extra argument.

### Creating entities

Use [new_entity!](@ref) to stage entity creation. An [Entity](@ref) ID is pre-allocated
immediately and returned, allowing it to be used in subsequent commands before [apply!](@ref)
is called. The returned entity is not considered alive until the buffer is applied.

```jldoctest
world = World(Position, Velocity);
buf = CommandBuffer(world, (NewEntityCommand((Position, Velocity)),));

e = new_entity!(buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)));
apply!(buf)

# output

CommandBuffer{World{Ark._WorldStorage{Tuple{Ark._ComponentStorage{Position, Vector{Position}}, Ark._ComponentStorage{Velocity, Vector{Velocity}}}, (0x0000000000000000,)}, Ark._WorldState{1, 0}}, NewEntityCommand{Tuple{Position, Velocity}}}(World(entities=1, comp_types=(Position, Velocity)), NewEntityCommand{Tuple{Position, Velocity}}[])
```

## Applying commands

Call [apply!](@ref) to execute all staged commands in FIFO order:

```jldoctest
world = World(Position, Velocity, Health);
buf = CommandBuffer(world, (
    NewEntityCommand((Position, Velocity)),
    AddComponentsCommand((Health,)),
));

e = new_entity!(buf, (Position(1.0, 2.0), Velocity(10.0, 20.0)));
add_components!(buf, e, (Health(1.0),));

apply!(buf)

# output

CommandBuffer{World{Ark._WorldStorage{Tuple{Ark._ComponentStorage{Position, Vector{Position}}, Ark._ComponentStorage{Velocity, Vector{Velocity}}, Ark._ComponentStorage{Health, Vector{Health}}}, (0x0000000000000000,)}, Ark._WorldState{1, 0}}, Union{AddComponentsCommand{Tuple{Health}}, NewEntityCommand{Tuple{Position, Velocity}}}}(World(entities=1, comp_types=(Position, Velocity, Health)), Union{AddComponentsCommand{Tuple{Health}}, NewEntityCommand{Tuple{Position, Velocity}}}[])
```

After `apply!` the buffer is cleared and can be reused.

### Recording arbitrary commands

To coordinate world changes with non-world state, include a custom command type in
the command specs, define `apply!(world, command)`, and record command values with
[`record!`](@ref):

```jldoctest
world = World(Position, Velocity, Health)

struct PushOnGridCommand
    grid::Matrix{Vector{Entity}}
    entity::Entity
end

function Ark.apply!(world, cmd::PushOnGridCommand)
    pos, = get_components(world, cmd.entity, (Position,))
    push!(cmd.grid[Int(pos.x), Int(pos.y)], cmd.entity)
    return
end

buf = CommandBuffer(world, (
    NewEntityCommand((Position,)),
    PushOnGridCommand,
))

grid = [Entity[] for _ in 1:2, _ in 1:2]

entity = new_entity!(buf, (Position(1.0, 1.0),))
record!(buf, PushOnGridCommand(grid, entity))

apply!(buf)

grid # now it contains the entity created in the buffer

# output

2×2 Matrix{Vector{Entity}}:
   [Entity(2, 1)]  []
   []              []
```
