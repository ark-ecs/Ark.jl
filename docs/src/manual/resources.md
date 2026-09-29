# Resources

[Resources](@ref resources-api) are singular data structures in an ECS [`World`](@ref).
As such, they can be thought of as [Components](@ref) that exist only once
and are not associated to an [`Entity`](@ref).
Examples could be the current game/simulation tick,
a grid that your entities live on, or an acceleration structure for spatial indexing.

## Creating resources

Resources can be of any type, but only one resource of a particular type can exist in a World.
They are simply added to the world with [`add_resource!`](@ref):

```@meta
DocTestSetup = quote
    using Ark

    world = World()
end
```

```jldoctest; output = false
struct Tick
    time::Int
end

add_resource!(world, Tick(0))

# output

Tick(0)
```

## Accessing resources

Resources can be retrieved via [`get_resource`](@ref):

```@meta
DocTestSetup = quote
    using Ark
        
    struct Tick
        time::Int
    end

    world = World()
    add_resource!(world, Tick(0))
end
```

```jldoctest; output = false
tick = get_resource(world, Tick)
time = tick.time

# output

0
```

As getting a resource is not particularly fast (≈10ns),
this should not be done in hot loops like queries, but beforehand.

The existence of a resource type in the World can be checked with [`has_resource`](@ref):

```@meta
DocTestSetup = quote
    using Ark
        
    struct Tick
        time::Int
    end

    world = World()
end
```

```jldoctest; output = false
if has_resource(world, Tick)
    # ...
end

# output

```

## Setting and removing resources

Resources can also be removed from the world using [`remove_resource!`](@ref),
or overwritten with [`set_resource!`](@ref), which is particularly useful for immutable types:

```@meta
DocTestSetup = quote
    using Ark
        
    struct Tick
        time::Int
    end

    world = World()
    add_resource!(world, Tick(0))
end
```

```jldoctest; output = false
set_resource!(world, Tick(1))
remove_resource!(world, Tick)

# output

Tick(1)
```
