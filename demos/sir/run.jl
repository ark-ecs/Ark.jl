
include("main.jl")
precompile(update_sim!, (typeof(World(S, I, R)), Slider, Slider, Slider))
app()
