# Changelog

## [[v0.3.0]](https://github.com/ark-ecs/Ark.jl/compare/v0.2.0...v0.3.0)

### Breaking changes

- Batch entity creation uses a callback/`do`-block instead of an iterator (#400)

### Features

- Adds entity relationships (#340, #349)
- Adds events for relationship changes (#370)
- Adds re-usable filters for query construction (#375, #413)
- Adds cached/registered filters for faster query iteration with many archetypes (#378)
- Adds batch entity removal (#396, #402)
- Adds batch-setting entity relation targets (#406)
- Adds batched versions of adding, removing and exchanging components (#408)
- Makes Ark compatible with [Mooncake.jl](https://github.com/chalk-lab/Mooncake.jl) (#405)

### Performance

- Uses a hash table for some component transitions, with up t0 30% speedup (#348)
- Uses `push!` instead of `resize!`+`setindex!` for moving and creating components (#439)
- Caches the last component transition, with 15-35% speedup (#448)

### Documentation

- Adds a chapter on Ark's architecture to the user manual (#391, #394)

### Bugfixes

- Fixes missing swaps in archetypes when removing components (#432, fixes #430)

### Other

- Ark.jl moved from the personal account of it's initiator to the [ark-ecs](https://github.com/ark-ecs) organization

## [[v0.2.0]](https://github.com/ark-ecs/Ark.jl/compare/v0.1.1...v0.2.0)

### Breaking changes

- Removes the macros for the convenient tuple syntax, the syntax is used in ordinary functions now (#305)
- Throws more explicit exception types instead of generic `ErrorException` (#202)
- Query argument `optional` adds further components instead of making existing ones optional (#253)

### Features

- Adds an event system with events for structural changes as well as custom events (#155)
- Adds storage modes Vector and StructArray, which can be selected per component type (#207, #225)
- Adds field view, so field access for query columns works equally for Vector and StructArray storages (#213)
- Adds support to manage an arbitrary number of components in the `World` (#230, #327, #330)
- Adds `@copy_entity!` for copying an entity and optionally adding and removing components (#262, #266)
- Adds keyword argument `initial_capacity` to World constructor (#288)
- Adds function `reset!` for resetting and reusing a world to avoid reallocations (#292)
- Adds function `length` for queries and batches (#298)
- Adds function `count_entities` for queries and batches (#316)

### Performance

- Adaptive bit-mask size, depending on the number of components in the world (#237, #250)
- Avoids unions in queries without optional components, speeding up query iteration (#246)

### Documentation

- Adds an animated logo demo (#268)
- Adds a basic SIR demo (#324)
- Adds a demo of an evolutionary model for grazers (#325)
- Adds a demo with travelers on a network (#334)
- Adds a boids/flocking demo (#337)
- Adds a page listing all demos with screenshots in the user manual (#339)

### Other

- Improves error messages when passing components types as `(A, B)` instead of the required `Val.((A, B))` (#191)
- Checks for duplicate components on query construction (#255)
- Improves string representations of all exposed types (#275)

## [[v0.1.1]](https://github.com/ark-ecs/Ark.jl/compare/v0.1.0...v0.1.1)

### Bugfixes

- Fix broken archetype pre-selection in queries (#301)

## [[v0.1.0]](https://github.com/ark-ecs/Ark.jl/tree/v0.1.0)

Initial release of Ark.jl.
