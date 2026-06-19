using Ark
using Colors
using GLMakie
using GeometryBasics
using CoherentNoise

include("../_common/scheduler.jl")
include("../_common/resources.jl")
include("../_common/terminate.jl")
include("components.jl")
include("resources.jl")
include("sys/grazer_init.jl")
include("sys/grass_growth.jl")
include("sys/grazer_movement.jl")
include("sys/grazer_feeding.jl")
include("sys/grazer_metabolism.jl")
include("sys/grazer_mortality.jl")
include("sys/grazer_decision.jl")
include("sys/grazer_reproduction.jl")
include("sys/grass_draw.jl")
include("sys/grazer_draw.jl")
include("sys/update_plots.jl")

const IS_CI = "CI" in keys(ENV)

function main()
    world = new_grazer_world()

    size = WorldSize(120, 100, 6)
    add_resource!(world, size)

    setup_makie(world, size)

    add_resource!(world, SimulationSpeed(1))

    scheduler = Scheduler(
        world,
        (
            GrazerInit(count=1000),
            GrassGrowth(growth_rate=0.01, feature_size=23.0),
            GrazerMovement(speed=0.1),
            GrazerFeeding(max_grazing=0.025, efficiency=1.0, threshold=0.1),
            GrazerReproduction(max_offspring=10, cross_rate=0.2, mutation_rate=0.01),
            GrazerMetabolism(base_rate=0.005, move_rate=0.01),
            GrazerMortality(),
            GrazerDecision(),
            GrassDraw(),
            GrazerDraw(),
            UpdatePlots(),
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

    size = (size.width * size.scale, size.height * size.scale)
    f = Figure(figure_padding=(2, 15, 2, 2), size=(size[1] + 245, size[2] + 4), backgroundcolor=:white)

    scene = LScene(
        f[1:3, 1], width=size[1], height=size[2],
        scenekw=(camera=(campixel!), size=size, backgroundcolor=:black),
    )

    data = PlotData()

    ax1 = Axis(f[1, 2],
        title="Search behavior",
        xlabel="Max angle ×90°",
        ylabel="Reverse prob. ×0.1",
        backgroundcolor=:white, alignmode=Outside())
    scatter!(ax1, data.max_angle, data.reverse_prob, color=:green, markersize=2)
    ylims!(ax1, low=0, high=1)
    xlims!(ax1, low=0, high=1)

    ax2 = Axis(f[2, 2], title="Movement thresholds",
        xlabel="Threshold move (rel.)",
        ylabel="Threshold graze",
        backgroundcolor=:white, alignmode=Outside())
    scatter!(ax2, data.move_thresh, data.graze_thresh, color=:green, markersize=2)
    ylims!(ax2, low=0, high=1)
    xlims!(ax2, low=0, high=1)

    ax3 = Axis(f[3, 2], title="Reproduction",
        xlabel="#Offspring ×10",
        ylabel="Energy share",
        backgroundcolor=:white, alignmode=Outside())
    scatter!(ax3, data.num_offspring, data.energy_share, color=:green, markersize=2)
    ylims!(ax3, low=0, high=1)
    xlims!(ax3, low=0, high=1)

    screen = display(f)
    GLMakie.GLFW.SetWindowTitle(screen.glscreen, "Grazers demo")

    add_resource!(world, Window(scene.scene, screen))
    add_resource!(world, data)
end

function run!(world::World, scheduler::Scheduler)
    initialize!(scheduler)

    window = get_resource(world, Window)
    speed = get_resource(world, SimulationSpeed)
    on(window.screen.render_tick) do _
        for _ in 1:speed.speed
            if !update!(scheduler)
                close(window.screen)
            end
        end
    end

    GLMakie.start_renderloop!(window.screen)
    wait(window.screen)
end

main()
