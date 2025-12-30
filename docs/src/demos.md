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

An model for the evolution of the foraging behavior of grazers.
Dynamically adds and removes components to handle behavioral states.
[Source code](https://github.com/ark-ecs/Ark.jl/tree/main/demos/grazers).

```@raw html
<div style="text-align: center;">
<img alt="SIR demo" src="https://raw.githubusercontent.com/ark-ecs/Ark.jl/refs/heads/gh-images/screenshots/grazers.png" />
</div>
```
