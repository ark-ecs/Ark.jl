using Ark
using Colors
using GLMakie

include("../_common/scheduler.jl")
include("../_common/resources.jl")
include("../_common/profile.jl")
include("../_common/terminate.jl")
include("components.jl")
include("resources.jl")
include("util.jl")
include("sys/network_init.jl")
include("sys/traveler_init.jl")
include("sys/traveler_movement.jl")
include("sys/network_plot.jl")
include("sys/traveler_plot.jl")

const IS_CI = "CI" in keys(ENV)

function main()
    world = World(Position, Node, Edge, EdgePosition, EdgeLength, Traveler, Color)

    size = WorldSize(800, 600)
    add_resource!(world, size)

    setup_makie(world, size)

    scheduler = Scheduler(
        world,
        (
            NetworkInit(distance=50),
            TravelerInit(count=250),
            TravelerMovement(speed=0.2),
            NetworkPlot(),
            TravelerPlot(),
            ProfilingSystem(60),
            TerminationSystem(IS_CI ? 240 : -1), # Short run in CI tests
        ),
    )

    run!(world, scheduler)
end

function setup_makie(world::World, size::WorldSize)
    GLMakie.activate!(
        framerate=60.0,
        vsync=true,
        renderloop=GLMakie.renderloop,
        render_on_demand=false,
        focus_on_show=(!IS_CI),
    )

    data = PlotData()
    add_resource!(world, data)

    f = Figure(size=(size.width, size.height), backgroundcolor=:white)

    ax = Axis(f[1, 1], aspect=DataAspect())
    hidedecorations!(ax)
    xlims!(ax, low=0, high=size.width)
    ylims!(ax, low=0, high=size.height)

    scatter!(ax, data.nodes, markersize=15, color=:lightgray)
    linesegments!(ax, data.edges, linewidth=10, color=:lightgray)
    scatter!(ax, data.travelers, color=data.colors, strokecolor=:black, strokewidth=1, markersize=8)

    screen = display(f)
    GLMakie.GLFW.SetWindowTitle(screen.glscreen, "Network demo")

    add_resource!(world, Window(screen))
end

function run!(world::World, scheduler::Scheduler)
    initialize!(scheduler)

    window = get_resource(world, Window)
    on(window.screen.render_tick) do _
        if !update!(scheduler)
            close(window.screen)
        end
    end

    GLMakie.start_renderloop!(window.screen)

    wait(window.screen)
end
