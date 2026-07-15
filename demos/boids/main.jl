using Ark
using GLMakie
using GeometryBasics

include("../_common/resources.jl")
include("../_common/scheduler.jl")
include("../_common/terminate.jl")
include("util.jl")
include("components.jl")
include("resources.jl")
include("sys/mouse.jl")
include("sys/boids_init.jl")
include("sys/boids_neighbors.jl")
include("sys/boids_movement.jl")
include("sys/boids_plot.jl")

const IS_CI = "CI" in keys(ENV)

function main()
    world = World(Position, Velocity, Rotation, Neighbors, UpdateStep)

    size = WorldSize(1000, 700)
    add_resource!(world, size)

    setup_makie(world, size)

    scheduler = Scheduler(
        world,
        (
            BoidsInit(count=1000),
            MouseSystem(),
            BoidsNeighbors(max_distance=18),
            BoidsMovement(
                avoid_factor=0.1,
                avoid_distance=6.0,
                cohesion_factor=0.002,
                align_factor=0.005,
                min_speed=0.5,
                max_speed=1.0,
                margin=150.0,
                margin_factor=0.1,
                mouse_radius=200.0,
                mouse_avoid_factor=1.0,
            ),
            BoidsPlot(),
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
    scene = Scene(camera=(campixel!), size=(size.width, size.height), backgroundcolor=:black)

    boid_shape = Polygon(Point2f[(2, 0), (-3, 4), (-1, 0), (-3, -4)])
    data = PlotData()

    meshscatter!(scene, data.positions; rotation=data.rotations, marker=boid_shape, color=:white, markersize=1)

    screen = display(scene)
    GLMakie.GLFW.SetWindowTitle(screen.glscreen, "Boids demo")

    add_resource!(world, data)
    add_resource!(world, Window(screen, scene))
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
