
struct WorldObservables
    pos::Observable{Vector{Point3f}}
    vel::Observable{Vector{Float64}}
    fps::Observable{String}
end

struct WorldFigure
    figure::Figure
end

struct NBodyPlot end

function initialize!(::NBodyPlot, world)
    pos_obs = Observable(Point3f[])
    vel_mag_obs = Observable(Float64[])
    marker_sizes = Float64[]

    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        append!(marker_sizes, (unpack(masses).val .^ (1 / 3)) .* 5.0)
    end
    update_observables!(pos_obs, vel_mag_obs, world)

    fig = Figure(size=(1200, 800), backgroundcolor=:black, figure_padding=0)
    ax = Axis3(fig[1, 1], title="Ark.jl Multi-Table N-Body Simulation",
        titlecolor=:white, azimuth=0.5pi, elevation=0)
    hidedecorations!(ax)
    hidespines!(ax)

    v = 100.0
    zoom_range = Observable(v)

    limits!(ax, -v, v, -v, v, -v, v)
    on(zoom_range) do z
        limits!(ax, -z, z, -z, z, -z, z)
    end

    on(events(fig).keyboardbutton) do event
        if event.action == Keyboard.press || event.action == Keyboard.repeat
            if event.key == Keyboard.up || event.key == Keyboard.equal
                zoom_range[] *= 0.9
            elseif event.key == Keyboard.down || event.key == Keyboard.minus
                zoom_range[] *= 1.1
            end
        end
    end

    points = scatter!(ax, pos_obs,
        color=vel_mag_obs,
        colormap=:gist_heat,
        markersize=marker_sizes,
        glowwidth=1,
        glowcolor=(:white, 0.2),
    )

    fps_obs = Observable("FPS: 0.0")
    Label(fig[1, 1], fps_obs, color=:white, halign=:left, valign=:top,
        padding=(10, 10, 10, 10), fontsize=20, tellwidth=false, tellheight=false)

    add_resource!(world, WorldObservables(pos_obs, vel_mag_obs, fps_obs))
    add_resource!(world, WorldFigure(fig))

    return
end

function update!(::NBodyPlot, world)
    obs = get_resource(world, WorldObservables)
    update_observables!(obs.pos, obs.vel, world)
end

# Bodies are spread over multiple tables, so observables must be collected across
# all tables before being set (query iteration yields one column set per table).
function update_observables!(pos_obs, vel_mag_obs, world)
    px_all = Float32[]
    py_all = Float32[]
    pz_all = Float32[]
    mag_all = Float64[]
    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        (px, py, pz) = unpack(positions)
        (vx, vy, vz) = unpack(velocities)
        append!(px_all, px)
        append!(py_all, py)
        append!(pz_all, pz)
        append!(mag_all, sqrt.(vx .^ 2 .+ vy .^ 2 .+ vz .^ 2))
    end
    pos_obs[] = Point3f.(px_all, py_all, pz_all)
    vel_mag_obs[] = mag_all
end
