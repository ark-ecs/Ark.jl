using Ark
using BenchmarkTools
using Printf
using KernelAbstractions
using CUDA
using GLMakie
using Random

include("components.jl")

const G = 1.0f0
const SOFTEN = 0.1f0

@kernel function velocity_kernel(positions, velocities, masses, n, dt)
    i = @index(Global)
    
    px, py, pz = positions
    px_i = px[i]
    py_i = py[i]
    pz_i = pz[i]

    accx = accy = accz = 0.0f0
    
    for j in 1:n
        i == j && continue
        
        @inbounds px_j, py_j, pz_j = px[j], py[j], pz[j]

        dx = px_j - px_i
        dy = py_j - py_i
        dz = pz_j - pz_i

        dist_sq = dx*dx + dy*dy + dz*dz + SOFTEN
        inv_dist = 1.0f0 / sqrt(dist_sq)
        inv_dist3 = inv_dist * inv_dist * inv_dist
        
        @inbounds m_j = masses.val[j]
        f = G * m_j * inv_dist3
        
        accx += f * dx
        accy += f * dy
        accz += f * dz
    end

    vx, vy, vz = velocities

    vx[i] += accx * dt
    vy[i] += accy * dt
    vz[i] += accz * dt

end

@kernel function position_kernel(positions, velocities, dt)
    i = @index(Global)

    positions.x[i] += velocities.x[i] * dt
    positions.y[i] += velocities.y[i] * dt
    positions.z[i] += velocities.z[i] * dt
end

function initialize_world(n, backend)
    T = (backend isa CUDABackend) ? GPUStructArray{:CUDA} : StructArray
    world = World(
        Position => Storage{T},
        Velocity => Storage{T},
        Mass => Storage{T},
    )

    for i in 1:n
        new_entity!(world, (
            Position(((randn(), randn(), randn()) .* 50.0f0)...),
            Velocity(((randn(), randn(), randn()) .* 0.01f0)...),
            Mass(randexp() * 10.0f0)
        ))
    end
    return world
end

function nbody_simulation(n, dt, backend)
    world = initialize_world(n, backend)

    vkernel = velocity_kernel(backend)
    pkernel = position_kernel(backend)

    fig, pos_obs, vel_mag_obs, fps_obs = initialize_figure(world)

    GC.gc()

    while isopen(fig.scene)
        t0 = time_ns()
        for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))

            vkernel(unpack(positions), unpack(velocities), unpack(masses),
                n, dt, ndrange=n, workgroupsize=256)
            KernelAbstractions.synchronize(backend)
            pkernel(unpack(positions), unpack(velocities),
                dt, ndrange=n, workgroupsize=256)
            KernelAbstractions.synchronize(backend)

            update_observables!(pos_obs, vel_mag_obs, positions, velocities)
        end
        t1 = time_ns()
        fps_obs[] = @sprintf("FPS: %.1f", 1e9 / (t1 - t0))
        sleep(max(0, 1/60 - (t1-t0) / 1e9))
        yield()
    end
end

function initialize_figure(world)

    pos_obs = Observable(Point3f[])
    vel_mag_obs = Observable(Float64[])
    marker_sizes = Float64[]

    for (entities, positions, velocities, masses) in Query(world, (Position, Velocity, Mass))
        append!(marker_sizes, (unpack(masses).val .^ (1/3)) .* 5.0)
        update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    end

    fig = Figure(size = (1200, 800), backgroundcolor = :black, figure_padding = 0)
    ax = Axis3(fig[1, 1], title = "Ark.jl N-Body Simulation", 
               titlecolor = :white, azimuth = 0.5pi, elevation=0)
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
        color = vel_mag_obs, 
        colormap = :gist_heat, 
        markersize = marker_sizes, 
        glowwidth = 1, 
        glowcolor = (:white, 0.2)
    )

    fps_obs = Observable("FPS: 0.0")
    Label(fig[1, 1], fps_obs, color = :white, halign = :left, valign = :top, 
          padding = (10, 10, 10, 10), fontsize = 20, tellwidth = false, tellheight = false)

    display(fig)

    return fig, pos_obs, vel_mag_obs, fps_obs
end

function update_observables!(pos_obs, vel_mag_obs, positions, velocities)
    (px, py, pz) = unpack(positions)
    (vx, vy, vz) = unpack(velocities)       
    pos_obs[] = Point3f.(px, py, pz)
    vel_mag_obs[] = sqrt.(vx.^2 .+ vy.^2 .+ vz.^2)
end

function run_demo(backend)
    n = 10000
    dt = 0.01f0
    nbody_simulation(n, dt, backend)
end

#run_demo(CPU())
run_demo(CUDABackend())
