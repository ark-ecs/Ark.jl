using Ark
using Documenter

DocMeta.setdocmeta!(Ark, :DocTestSetup, :(using Ark); recursive=true)

if !("--skip-tests" in ARGS)
    doctest(Ark)
end

#! format: off
makedocs(;
    modules  = [Ark],
    sitename = "Ark.jl",
    authors  = "Martin Lange <martin_lange_@gmx.net>, Adriano Meligrana <adriano.meligrana@centai.eu>",
    format   = Documenter.HTML(;
        description="Ark.jl is an archetype-based Entity Component System (ECS) for Julia.",
        canonical="https://ark-ecs.github.io/Ark.jl/stable",
        edit_link="main",
        prettyurls=false,
        sidebar_sitename=false,
        assets=["assets/favicon.ico", "assets/custom.css"]
    ),
    pages    = [
        "Home" => "index.md",
        "Manual" => [
            "manual/quickstart.md",
            "manual/world.md",
            "manual/entities.md",
            "manual/components.md",
            "manual/queries.md",
            "manual/systems.md",
            "manual/resources.md",
            "manual/relations.md",
            "manual/batch.md",
            "manual/events.md",
            "manual/architecture.md"
        ],
        "Demos" => "demos.md",
        "Benchmarks" => "benchmarks.md",
        "Public API" => "api.md",
    ],
    warnonly = false,
)
#! format: on

deploydocs(;
    repo="github.com/ark-ecs/Ark.jl.git",
    versions=[
        "stable" => "v^",
        "dev" => "main",
    ],
)
