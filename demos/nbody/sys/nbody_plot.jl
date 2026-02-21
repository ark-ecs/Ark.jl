
struct NBodyPlot end

function initialize!(::NBodyPlot, world)
    pos_obs = Observable(Point3f[])
    vel_mag_obs = Observable(Float64[])
    marker_sizes = Float64[]

    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        append!(marker_sizes, (unpack(masses).val .^ (1/3)) .* 5.0)
        update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    end

    fig = Figure(size=(1200, 800), backgroundcolor=:black, figure_padding=0)
    ax = Axis3(fig[1, 1], title="Ark.jl N-Body Simulation",
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
    pos_obs, vel_mag_obs = obs.pos, obs.vel
    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    end
end

function update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    (px, py, pz) = unpack(positions)
    (vx, vy, vz) = unpack(velocities)
    pos_obs[] = Point3f.(px, py, pz)
    vel_mag_obs[] = sqrt.(vx .^ 2 .+ vy .^ 2 .+ vz .^ 2)
end
