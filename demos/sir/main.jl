
using GLMakie

include("model.jl")

const IS_CI = "CI" in keys(ENV)
GLMakie.activate!(render_on_demand=false, focus_on_show=(!IS_CI))

function record_frame!(world, obs_S, obs_I, obs_R)
    s_count = get_count(world, S)
    i_count = get_count(world, I)
    r_count = get_count(world, R)

    t = get_resource(world, Time).time
    push!(obs_S[], Point2f(t, s_count))
    push!(obs_I[], Point2f(t, i_count))
    push!(obs_R[], Point2f(t, r_count))

    notify(obs_S)
    notify(obs_I)
    notify(obs_R)
end

function reset_sim!(world, obs_S, obs_I, obs_R, btn_run, ax, sl_N, sl_r, sl_beta)
    btn_run.label[] = "Run"

    Parameters.@unpack N, I0, beta, c, r, dt = get_resource(world, Params)
    buffer = get_resource(world, BufferType)
    reset!(world)
    N, beta, r = sl_N.value[], sl_beta.value[], sl_r.value[]
    initialize_world!(world, N, I0, beta, c, r, dt, buffer)
    get_resource(world, Terminate).stop = true

    empty!(obs_S[])
    empty!(obs_I[])
    empty!(obs_R[])

    record_frame!(world, obs_S, obs_I, obs_R)
end

function update_sim!(world, sl_N, sl_r, sl_beta)
    N, beta, r = sl_N.value[], sl_beta.value[], sl_r.value[]
    params = get_resource(world, Params)
    if N > params.N
        new_entities!(world, N - params.N, (S(),))
    elseif N < params.N
        all_entities = get_resource(world, BufferType).ents
        resize!(all_entities, 0)
        for (entities,) in Query(world, ())
            append!(all_entities, entities)
        end
        shuffle!(all_entities)
        for i in 1:(params.N-N)
            remove_entity!(world, all_entities[i])
        end
    end
    params.N = N
    params.beta = beta
    params.r = r
end

function app()
    dt = 0.1
    c = 10.0
    I0 = 5

    # Initial default values
    default_N = 10_000
    default_beta = 0.05
    default_r = 0.25

    fig = Figure(size=(1000, 600), fontsize=18)

    ax = Axis(fig[1, 1],
        title  = "SIR Model Trajectory",
        xlabel = "Time",
        ylabel = "Population",
    )

    controls = GridLayout(fig[2, 1])

    lbl_N = Label(controls[1, 1], "Population (N):")
    sl_N = Slider(controls[1, 2], range=[10^x for x in 1:6], startvalue=default_N)
    lbl_N_val = Label(controls[1, 3], lift(x -> "$(x)", sl_N.value), width=100, halign=:left)

    lbl_beta = Label(controls[2, 1], "Infection Rate (beta):")
    sl_beta = Slider(controls[2, 2], range=0.0:0.01:1.0, startvalue=default_beta)
    lbl_beta_val = Label(controls[2, 3], lift(x -> "$(round(x, digits=2))", sl_beta.value), halign=:left)

    lbl_r = Label(controls[3, 1], "Recovery Rate (r):")
    sl_r = Slider(controls[3, 2], range=0.0:0.01:1.0, startvalue=default_r)
    lbl_r_val = Label(controls[3, 3], lift(x -> "$(round(x, digits=2))", sl_r.value), halign=:left)

    lbl_fps = Label(controls[4, 1], "Simulation FPS:")
    sl_fps = Slider(controls[4, 2], range=[2^x for x in 1:10], startvalue=2^6)
    lbl_fps_val = Label(controls[4, 3], lift(x -> "$(x)", sl_fps.value), halign=:left)

    btn_run = Button(controls[5, 1], label="Run", width=100, tellwidth=false)
    btn_reset = Button(controls[5, 2], label="Reset", width=100, tellwidth=false)

    colgap!(controls, 10)
    rowgap!(controls, 10)

    obs_S = Observable(Point2f[])
    obs_I = Observable(Point2f[])
    obs_R = Observable(Point2f[])

    lines!(ax, obs_S, color=:blue, label="Susceptible", linewidth=3)
    lines!(ax, obs_I, color=:red, label="Infected", linewidth=3)
    lines!(ax, obs_R, color=:green, label="Recovered", linewidth=3)
    axislegend(ax)

    world = new_world(default_N)
    initialize_world!(world, default_N, I0, default_beta, c, default_r, dt)
    get_resource(world, Terminate).stop = true

    on(btn_run.clicks) do _
        get_resource(world, Terminate).stop = !get_resource(world, Terminate).stop
        btn_run.label[] = !get_resource(world, Terminate).stop ? "Pause" : "Run"
    end

    on(btn_reset.clicks) do _
        reset_sim!(world, obs_S, obs_I, obs_R, btn_run, ax, sl_N, sl_r, sl_beta)
    end

    on(sl_N.value) do _
        update_sim!(world, sl_N, sl_r, sl_beta)
    end
    on(sl_r.value) do _
        update_sim!(world, sl_N, sl_r, sl_beta)
    end
    on(sl_beta.value) do _
        update_sim!(world, sl_N, sl_r, sl_beta)
    end

    screen = display(fig)
    autolimits!(ax)
    GC.gc()
    t_tot = 0.0
    @async while true
        if IS_CI || get_resource(world, Terminate).stop == false
            t0 = time_ns()
            step_world!(world)
            record_frame!(world, obs_S, obs_I, obs_R)
            autolimits!(ax)
            if get_count(world, I) == 0
                IS_CI && close(screen)
                get_resource(world, Terminate).stop = true
                btn_run.label[] = "Run"
                t_tot = 0.0
            end
            t1 = time_ns()
            t_tot += (t1 - t0)
            sleep_every = max(1, exponent(sl_fps.value[]) - 3)
            if get_resource(world, Tick).tick % sleep_every == 0
                sleep(max(0, sleep_every / sl_fps.value[] - t_tot / 10^9))
                t_tot = 0.0
            end
        else
            sleep(0.1)
        end
    end

    wait(screen)
end

precompile(update_sim!, (typeof(World(S, I, R)), Slider, Slider, Slider))
app()
