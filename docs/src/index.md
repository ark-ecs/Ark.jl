```@raw html
<div style="text-align: center;">

<img src="assets/ark-logo-text-light.svg" class="only-light" alt="Ark.jl (logo)" />
<img src="assets/ark-logo-text-dark.svg" class="only-dark" alt="Ark.jl (logo)" />
```

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

[Ark.jl](https://github.com/ark-ecs/Ark.jl) is an archetype-based [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) (ECS) for [Julia](https://julialang.org/).
It is a port of the Go ECS [Ark](https://github.com/mlange-42/ark).

```@raw html
&mdash;&mdash;
</div>
```

## Features

- Designed for [performance](@ref Benchmarks) and highly optimized.
- Well-documented, type-stable [API](@ref).
- [Entity relationships](@ref) as a first-class feature.
- [Storage mode](@ref component-storages) per component for ergonomics and SIMD.
- Extensible [event system](@ref "Event system") with filtering and custom event types.
- Fast [batch operations](@ref "Batch operations") for mass manipulation.
- No [systems](@ref Systems). Just [queries](@ref Queries). Use your own structure.
- Minimal [dependencies](https://github.com/ark-ecs/Ark.jl/blob/main/Project.toml), 100% [test coverage](https://app.codecov.io/github/ark-ecs/ark.jl).

## Why ECS?

Entity Component Systems (ECS) offer a clean, scalable way to build individual- and agent-based models
by separating agent data from behavioral logic.
Agents are simply collections of components, while systems define how those components interact,
making simulations modular, extensible, and efficient even with millions of heterogeneous individuals.

Ark.jl brings this architecture to Julia with a lightweight, performance-focused implementation
that empowers scientific modellers to design complex and performant simulations
without the need for deep software engineering expertise.

## Manual Outline

- [Quickstart](@ref)
- [The World](@ref)
- [Entities](@ref)
- [Components](@ref)
- [Queries](@ref)
- [Systems](@ref)
- [Resources](@ref)
- [Entity relationships](@ref)
- [Batch operations](@ref)
- [Event system](@ref)
- [Architecture](@ref)

[Demos](@ref)

[Benchmarks](@ref)

## API Outline

```@contents
Pages = ["api.md"]
Depth = 2:2
```

## API Index

```@index
Pages = ["api.md"]
```

## Cite as

Lange, M. & Meligrana, A. (2025): Ark.jl – An archetype-based Entity Component System for Julia. DOI: [10.5281/zenodo.17512271](https://doi.org/10.5281/zenodo.17512271), GitHub repository: [https://github.com/ark-ecs/Ark.jl](https://github.com/ark-ecs/Ark.jl)
