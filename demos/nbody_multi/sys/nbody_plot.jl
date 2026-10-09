
struct NBodyPlot end

struct WorldObservables
    pos::Observable{Vector{Point3f}}
    vel::Observable{Vector{Float64}}
    bh_pos::Observable{Vector{Point3f}}
    fps::Observable{String}
end

struct WorldFigure
    figure::Figure
end

function initialize!(::NBodyPlot, world)
    config = get_resource(world, BlackHoleConfig)

    pos_obs = Observable(Point3f[])
    vel_mag_obs = Observable(Float64[])
    marker_sizes = Float64[]

    # Bodies only; the black holes are drawn separately below.
    for (_, positions, velocities, masses) in Query(world, (Position, Velocity, Mass); without=(BlackHole,))
        append!(marker_sizes, (unpack(masses).val .^ (1 / 3)) .* 5.0)
        update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    end

    bh_pos_obs = Observable(Point3f[])
    bh_size = min(60.0, 5.0 * config.mass^(1 / 3))

    fig = Figure(size=(1200, 800), backgroundcolor=:black, figure_padding=0)
    ax = Axis3(fig[1, 1], title="Ark.jl FlatQuery N-Body Simulation",
        titlecolor=:white, azimuth=0.5pi, elevation=0)
    hidedecorations!(ax)
    hidespines!(ax)

    # The view is sized to cover the black hole's spawn position from the
    # start, so the camera does not need to move when it appears.
    v = 1.2 * config.distance
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

    # Velocity coloring uses a fixed scale: with an auto-scaled range, the first
    # body slingshotting past the black hole (|v| > 1e5) would push every other
    # body to the cold end of the colormap, making them appear to lose speed.
    scatter!(ax, pos_obs,
        color=vel_mag_obs,
        colormap=:gist_heat,
        colorrange=(0.0, 150.0),
        markersize=marker_sizes,
        glowwidth=1,
        glowcolor=(:white, 0.2),
    )

    # Black hole: dark core with a bright accretion glow.
    scatter!(ax, bh_pos_obs,
        color=:black,
        markersize=bh_size,
        glowwidth=6,
        glowcolor=(:gold, 0.9),
    )

    fps_obs = Observable("FPS: 0.0")
    Label(fig[1, 1], fps_obs, color=:white, halign=:left, valign=:top,
        padding=(10, 10, 10, 10), fontsize=20, tellwidth=false, tellheight=false)

    add_resource!(world, WorldObservables(pos_obs, vel_mag_obs, bh_pos_obs, fps_obs))
    add_resource!(world, WorldFigure(fig))

    return
end

function update!(::NBodyPlot, world)
    obs = get_resource(world, WorldObservables)
    update_observables!(obs.pos, obs.vel, world)
    update_black_hole_observable!(obs.bh_pos, world)
end

# Bodies are spread over tables, so observables must be collected across all
# body tables before being set (query iteration yields one column set per
# table). The black hole has its own table and is excluded here.
function update_observables!(pos_obs, vel_mag_obs, world)
    px_all = Float32[]
    py_all = Float32[]
    pz_all = Float32[]
    mag_all = Float64[]
    for (_, positions, velocities) in Query(world, (Position, Velocity); without=(BlackHole,))
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

function update_black_hole_observable!(bh_pos_obs, world)
    px_all = Float32[]
    py_all = Float32[]
    pz_all = Float32[]
    for (_, positions) in Query(world, (Position,); with=(BlackHole,))
        (px, py, pz) = unpack(positions)
        append!(px_all, px)
        append!(py_all, py)
        append!(pz_all, pz)
    end
    bh_pos_obs[] = Point3f.(px_all, py_all, pz_all)
    return
end

function update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    (px, py, pz) = unpack(positions)
    (vx, vy, vz) = unpack(velocities)
    pos_obs[] = Point3f.(px, py, pz)
    vel_mag_obs[] = sqrt.(vx .^ 2 .+ vy .^ 2 .+ vz .^ 2)
end
