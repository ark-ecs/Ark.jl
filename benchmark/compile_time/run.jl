# Driver: sweeps the number of component types, measures first-call compile time of the
# default and type-erased dispatch at each point (one fresh worker process per point, so
# every measurement is a cold compile), writes a CSV, and renders the light/dark figures
# used in the docs.
#
# Not meant for CI - it is a one-off used to (re)generate the docs figure.
#
#     julia --project=benchmark benchmark/compile_time/run.jl

using DataFrames
using CSV
using Plots
using Printf

const HERE = @__DIR__
const REPO = normpath(joinpath(HERE, "..", ".."))
const WORKER = joinpath(HERE, "measure.jl")
const PROJECT = dirname(Base.active_project())  # run workers in this same instantiated env
const JULIA = first(Base.julia_cmd())           # same interpreter that runs this driver

const NS = [10, 30, 50, 100, 150, 250, 350, 500, 650, 800, 1000, 1200, 1500, 2000, 2500, 3000, 4000, 5000]
const K_SITES = 1

const OUT_DIR = joinpath(REPO, "docs", "src", "assets", "images")
const CSV_PATH = joinpath(HERE, "compile_time.csv")

function collect_data()
    rows = NamedTuple{(:N, :mode, :ctor, :ops, :mem),Tuple{Int,String,Float64,Float64,Float64}}[]
    for n in NS
        for erased in ("false", "true")
            @info "measuring N=$n, erased=$erased"
            out = read(`$JULIA --project=$PROJECT $WORKER $n $K_SITES $erased`, String)
            for line in split(strip(out), '\n')
                isempty(line) && continue
                n_s, mode, ctor_s, ops_s, mem_s = split(line, ',')
                push!(rows, (N=parse(Int, n_s), mode=String(mode),
                    ctor=parse(Float64, ctor_s), ops=parse(Float64, ops_s),
                    mem=parse(Float64, mem_s)))
            end
        end
        println(DataFrame(rows))
    end
    return DataFrame(rows)
end

function plot_compile(df::DataFrame, out_file::String; dark::Bool)
    family = "Courier"
    default(background_color=:transparent, fontfamily=family)
    fg = dark ? :white : :black
    color_default = dark ? "#e74c3c" : "#c0392b"
    color_erased = dark ? "#1abc9c" : "#2e63b8"
    default(foreground_color=fg)
    default(legendfont=font(family, 10, color=fg))
    default(xtickfont=font(family, 10, color=fg))
    default(ytickfont=font(family, 10, color=fg))
    default(guidefont=font(family, 11, color=fg))
    default(titlefont=font(family, 12, color=fg))

    plt = plot(
        title="Compile time of structural operations",
        xlabel="Number of component types",
        ylabel="First-call compile time [s]",
        size=(640, 400),
        xlim=(0, maximum(df.N) * 1.03),
        ylim=(0, NaN),
        legend=:topleft,
    )

    # Plot only the structural-operations compile time: world construction is identical in
    # both modes and would just dilute the difference the erased dispatch actually makes.
    for (mode, label, color) in
        (("default", "default (branch per component)", color_default),
         ("erased", "erased", color_erased))
        sub = sort(filter(r -> r.mode == mode, df), :N)
        plot!(sub.N, sub.ops, label=label, lw=2.0, color=color, marker=:circle, ms=3.5, msc=color)
    end

    savefig(plt, out_file)
    @info "wrote $out_file"
end

function plot_memory(df::DataFrame, out_file::String; dark::Bool)
    family = "Courier"
    default(background_color=:transparent, fontfamily=family)
    fg = dark ? :white : :black
    color_default = dark ? "#e74c3c" : "#c0392b"
    color_erased = dark ? "#1abc9c" : "#2e63b8"
    default(foreground_color=fg)
    default(legendfont=font(family, 10, color=fg))
    default(xtickfont=font(family, 10, color=fg))
    default(ytickfont=font(family, 10, color=fg))
    default(guidefont=font(family, 11, color=fg))
    default(titlefont=font(family, 12, color=fg))

    plt = plot(
        title="Peak process memory",
        xlabel="Number of component types",
        ylabel="Peak resident memory [GB]",
        size=(640, 400),
        xlim=(0, maximum(df.N) * 1.03),
        ylim=(0, NaN),
        legend=:topleft,
    )

    for (mode, label, color) in
        (("default", "default (branch per component)", color_default),
         ("erased", "erased", color_erased))
        sub = sort(filter(r -> r.mode == mode, df), :N)
        plot!(sub.N, sub.mem ./ 2^30, label=label, lw=2.0, color=color, marker=:circle, ms=3.5, msc=color)
    end

    savefig(plt, out_file)
    @info "wrote $out_file"
end

df = collect_data()
CSV.write(CSV_PATH, df)
@info "wrote $CSV_PATH"

mkpath(OUT_DIR)
plot_compile(df, joinpath(OUT_DIR, "bench_erased_compile_light.svg"); dark=false)
plot_compile(df, joinpath(OUT_DIR, "bench_erased_compile_dark.svg"); dark=true)
plot_memory(df, joinpath(OUT_DIR, "bench_erased_memory_light.svg"); dark=false)
plot_memory(df, joinpath(OUT_DIR, "bench_erased_memory_dark.svg"); dark=true)

# Console summary: structural-operations compile time (what the plot shows), plus the
# world-construction cost that is shared by both modes, for reference.
println("\nN     ops default(s)  ops erased(s)  ops speedup   ctor(s)   mem def(GB)  mem era(GB)")
for n in NS
    d = only(filter(r -> r.N == n && r.mode == "default", df))
    e = only(filter(r -> r.N == n && r.mode == "erased", df))
    @printf("%-5d %13.2f  %13.2f  %10.2fx  %8.2f  %11.2f  %11.2f\n",
        n, d.ops, e.ops, d.ops / e.ops, d.ctor, d.mem / 2^30, e.mem / 2^30)
end
