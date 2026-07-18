# Demos

The Ark repository contains a number of runnable [demos](https://github.com/ark-ecs/Ark.jl/tree/main/demos).
These are listed here, alongside instructions for running them.

## Running a demo

```@raw html
<details>
<summary><b>Click for instructions</b></summary>
<br/>
<p>
First, clone the repository and `cd` into it:
</p>

<pre><code class="language-shell hljs">git clone https://github.com/ark-ecs/Ark.jl.git
cd Ark.jl
</code></pre>

<p>
Next, instantiate the demos project:
</p>

<pre><code class="language-shell hljs">julia --project=demos -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
</code></pre>

<p>
Run individual demos like this:
</p>

<pre><code class="language-shell hljs">julia --project=demos demos/&lt;DEMO&gt;/main.jl
</code></pre>

<p>
Most of the demos are interactive, so try hovering the mouse over the window.
</p>

</details>
```

## Logo

An animated, interactive Ark.jl logo.
Use only the most basic features of Ark.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/logo).

```@raw html
<div style="text-align: center;">
<img alt="Logo demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/logo.png" />
</div>
```

## SIR

A simple individual-based epidemiologic SIR model.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/sir).

```@raw html
<div style="text-align: center;">
<img alt="SIR demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/sir.png" />
</div>
```

## Boids

Boids model, resembling bird flocks or fish schools.
Makes use of entities stored in a spatial acceleration structure, as well as in components.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/boids).

```@raw html
<div style="text-align: center;">
<img alt="SIR demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/boids.png" />
</div>
```

## Network

Random travelers on a network.
Makes massive use of entities stored in components.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/network).

```@raw html
<div style="text-align: center;">
<img alt="SIR demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/network.png" />
</div>
```

## Grazers

A model for the evolution of the foraging behavior of grazers.
Dynamically adds and removes components to handle behavioral states.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/grazers).

```@raw html
<div style="text-align: center;">
<img alt="SIR demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/grazers.png" />
</div>
```

## NBody

A model simulating the [n-body problem](https://en.wikipedia.org/wiki/N-body_problem), where particles interact through gravitational forces.
Exploits GPU computing for performance.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/nbody).

```@raw html
<div style="text-align: center;">
<img alt="NBody demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/nbody.png" />
</div>
```

## Forest

A continental-scale, individual-based forest — every tree is one entity, backed
by out-of-core `DiskVector` storage. It is a grid-structured demographic (gap)
model: trees compete for light via a per-cell canopy profile
(Beer–Lambert / Perfect-Plasticity-Approximation), draw on a per-cell soil-water
bucket (random annual rainfall, transpiration scaled by leaf area), grow with
saturating allometry, die from shading, drought, age or crowding, and regenerate
into gaps by reviving dead slots — so the archetype stays frozen and the dataset
is written once. Watch the canopy-height map develop while the side panels show
self-thinning, canopy maturation, mortality/recruitment and annual rainfall:
species composition shifts from pioneers to shade-tolerant climax trees (classic
succession), and dry years drive drought dieback followed by recruitment pulses.
Component layout keeps every hot system reading only small columns while a fat,
cold per-tree ring record stays on disk, so the world can far exceed RAM.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/forest).

The interactive demo runs at an in-RAM scale by default; set `FOREST_TARGET_GB`
(or `FOREST_TREES`) to grow it. A separate headless benchmark demonstrates the
out-of-core behaviour and the amortised use of `partition_entities!`:

```shell
julia --project=demos demos/forest/benchmark.jl                 # ~2 GB
FOREST_TARGET_GB=100 julia --project=demos demos/forest/benchmark.jl
```

To measure the genuine out-of-core path on a machine with less RAM than the
dataset, cap memory so the page cache cannot hold it:

```shell
systemd-run --user --scope -p MemoryMax=2G -p MemorySwapMax=0 \
  env FOREST_TARGET_GB=8 FOREST_PASSES=12 \
  julia --project=demos demos/forest/benchmark.jl
```

```@raw html
<div style="text-align: center;">
<img alt="Forest demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/forest.png" />
</div>
```
