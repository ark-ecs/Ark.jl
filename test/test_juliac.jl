include("../demos/sir/model.jl")

function @main(args)
    N = 10000
    I0 = 5
    beta = 0.05
    c = 10.0
    r = 0.25
    dt = 0.1

    world = new_world(N)
    initialize_world!(world, N, I0, beta, c, r, dt)

    for i in 1:10000
        step_world!(world)

        s_count = get_count(world, S)
        i_count = get_count(world, I)
        r_count = get_count(world, R)

        if i_count == 0
            println(Core.stdout, "Tick $i counts - S: $s_count, I: $i_count, R: $r_count")
            break
        elseif i == 1 || i % 100 == 0
            println(Core.stdout, "Tick $i counts - S: $s_count, I: $i_count, R: $r_count")
        end
    end

    tick = get_resource(world, Tick).tick
    println(Core.stdout, "SIR simulation completed in $tick ticks")

    return 0
end
