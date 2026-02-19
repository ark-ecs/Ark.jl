<div align="center" width="100%">
<a href="https://github.com/ark-ecs/ark.jl">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/main/docs/src/assets/ark-logo-text-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/main/docs/src/assets/ark-logo-text-light.svg">
  <img alt="Ark.jl Logo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/main/docs/src/assets/ark-logo-text-light.svg">
</picture>
</a>

[![Build Status](https://github.com/ark-ecs/Ark.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ark-ecs/Ark.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ark-ecs/Ark.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ark-ecs/Ark.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![JET](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)
[![Docs stable](https://img.shields.io/badge/docs-stable-blue?logo=julia)](https://ark-ecs.github.io/Ark.jl/stable/)
[![Docs dev](https://img.shields.io/badge/docs-dev-blue?logo=julia)](https://ark-ecs.github.io/Ark.jl/dev/)
[![GitHub](https://img.shields.io/badge/github-repo-blue?logo=github)](https://github.com/ark-ecs/Ark.jl)
[![DOI:10.5281/zenodo.17512271](https://img.shields.io/badge/10.5281%2Fzenodo.17512271-blue?label=doi)](https://doi.org/10.5281/zenodo.17512271)
[![MIT license](https://img.shields.io/badge/MIT-brightgreen?label=license)](https://github.com/ark-ecs/Ark.jl/blob/main/LICENSE-MIT)
[![Apache 2.0 license](https://img.shields.io/badge/Apache%202.0-brightgreen?label=license)](https://github.com/ark-ecs/Ark.jl/blob/main/LICENSE-APACHE)

Ark.jl is an archetype-based [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) (ECS) for [Julia](https://julialang.org/).
It is a port of the Go ECS [Ark](https://github.com/mlange-42/ark).

&mdash;&mdash;

[Features](#features) &nbsp; &bull; &nbsp; [Why ECS?](#why-ecs) &nbsp; &bull; &nbsp; [Installation](#installation) &nbsp; &bull; &nbsp; [Usage](#usage)
</div>

## Features

- Designed for [performance](https://ark-ecs.github.io/Ark.jl/stable/benchmarks) and highly optimized.
- Well-[documented](https://ark-ecs.github.io/Ark.jl/stable/), type-stable [API](https://ark-ecs.github.io/Ark.jl/stable/api).
- [Entity relationships](https://ark-ecs.github.io/Ark.jl/stable/manual/relations.html) as a first-class feature.
- [Storage mode](https://ark-ecs.github.io/Ark.jl/stable/manual/components.html#component-storages) per component for ergonomics and SIMD.
- Extensible [event system](https://ark-ecs.github.io/Ark.jl/stable/manual/events.html) with filtering and custom event types.
- Fast [batch operations](https://ark-ecs.github.io/Ark.jl/stable/manual/batch.html) for mass manipulation.
- No [systems](https://ark-ecs.github.io/Ark.jl/stable/manual/systems). Just [queries](https://ark-ecs.github.io/Ark.jl/stable/manual/queries). Use your own structure.
- Minimal [dependencies](https://github.com/ark-ecs/Ark.jl/blob/main/Project.toml), 100% [test coverage](https://app.codecov.io/github/ark-ecs/ark.jl).

## Why ECS?

Entity Component Systems (ECS) offer a clean, scalable way to build individual- and agent-based models
by separating agent data from behavioral logic.
Agents are simply collections of components, while systems define how those components interact,
making simulations modular, extensible, and efficient even with millions of heterogeneous individuals.

Ark.jl brings this architecture to Julia with a lightweight, performance-focused implementation
that empowers scientific modellers to design complex and performant simulations
without the need for deep software engineering expertise.

## Installation

Run this to add Ark.jl to a Julia project:

```julia
using Pkg
Pkg.add("Ark")
```

## Usage

Here is the classical Position/Velocity example that every ECS shows in the docs.

See the [Manual](https://ark-ecs.github.io/Ark.jl/stable/), [API docs](https://ark-ecs.github.io/Ark.jl/stable/api)
and [demos](https://github.com/ark-ecs/Ark.jl/tree/main/demos) for more details.

```julia
using Ark

"""Position component"""
struct Position
    x::Float64
    y::Float64
end

"""Velocity component"""
struct Velocity
    dx::Float64
    dy::Float64
end

# Create a world with the required components
world = World(Position, Velocity)

for i in 1:1000
    # Create an entity with components
    entity = new_entity!(world, (Position(i, i * 2), Velocity(1, 1)))
end

# Time loop
for i in 1:10
    # Iterate a query (archetypes)
    for (entities, positions, velocities) in Query(world, (Position, Velocity))
        # Iterate entities in the current archetype
        @inbounds for i in eachindex(entities)
            # Get components of the current entity
            pos = positions[i]
            vel = velocities[i]
            # Update an (immutable) component
            positions[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
end
```

## Cite as

Lange, M. & Meligrana, A. (2025): Ark.jl – An archetype-based Entity Component System for Julia. DOI: [10.5281/zenodo.17512271](https://doi.org/10.5281/zenodo.17512271), GitHub repository: https://github.com/ark-ecs/Ark.jl

## License

Ark.jl and all its sources and documentation are distributed under the [MIT license](https://github.com/ark-ecs/Ark.jl/blob/main/LICENSE-MIT) and the [Apache 2.0 license](https://github.com/ark-ecs/Ark.jl/blob/main/LICENSE-APACHE), as your options.
