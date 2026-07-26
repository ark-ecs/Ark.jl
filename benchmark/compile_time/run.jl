# Driver: sweeps the number of component types, measures first-call compile time of the four
# world modes at each point (one fresh worker process per point, so every measurement is a
# cold compile), writes a CSV, and renders the light/dark figures used in the docs.
#
# The two knobs are independent, so the sweep is a 2x2: `erased` selects how per-component
# operations are dispatched, `boxed` selects how the storages are held. They show up in
# different columns - `erased` in the cost of the structural operations, `boxed` in the cost
# of world construction and in memory - which is why all three are plotted.
#
# Not meant for CI - it is a one-off used to (re)generate the docs figures.
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

# The four world modes. Colour encodes the dispatch mode, line style encodes the storage
# layout, so the two knobs stay readable as separate effects.
const MODES = (
    (erased=false, boxed=false, mode="default", box="unboxed", label="default", dispatch=:default, style=:solid),
    (erased=false, boxed=true, mode="default", box="boxed", label="default + boxed", dispatch=:default, style=:dash),
    (erased=true, boxed=false, mode="erased", box="unboxed", label="erased", dispatch=:erased, style=:solid),
    (erased=true, boxed=true, mode="erased", box="boxed", label="erased + boxed", dispatch=:erased, style=:dash),
)

const OUT_DIR = joinpath(REPO, "docs", "src", "assets", "images")
const CSV_PATH = joinpath(HERE, "compile_time.csv")

function collect_data()
    rows = NamedTuple{(:N, :mode, :boxed, :ctor, :ops, :mem),Tuple{Int,String,String,Float64,Float64,Float64}}[]
    for n in NS
        for m in MODES
            @info "measuring N=$n, erased=$(m.erased), boxed=$(m.boxed)"
            out = read(`$JULIA --project=$PROJECT $WORKER $n $K_SITES $(m.erased) $(m.boxed)`, String)
            for line in split(strip(out), '\n')
                isempty(line) && continue
                n_s, mode_s, boxed_s, ctor_s, ops_s, mem_s = split(line, ',')
                push!(rows, (N=parse(Int, n_s), mode=String(mode_s), boxed=String(boxed_s),
                    ctor=parse(Float64, ctor_s), ops=parse(Float64, ops_s),
                    mem=parse(Float64, mem_s)))
            end
        end
        println(DataFrame(rows))
    end
    return DataFrame(rows)
end

_series(df::DataFrame, m) = sort(filter(r -> r.mode == m.mode && r.boxed == m.box, df), :N)

function _style!(dark::Bool)
    family = "Courier"
    fg = dark ? :white : :black
    default(background_color=:transparent, fontfamily=family)
    default(foreground_color=fg)
    default(legendfont=font(family, 10, color=fg))
    default(xtickfont=font(family, 10, color=fg))
    default(ytickfont=font(family, 10, color=fg))
    default(guidefont=font(family, 11, color=fg))
    default(titlefont=font(family, 12, color=fg))
    return (
        default=dark ? "#e74c3c" : "#c0392b",
        erased=dark ? "#1abc9c" : "#2e63b8",
    )
end

function plot_metric(
    df::DataFrame,
    out_file::String;
    dark::Bool,
    column::Symbol,
    title::String,
    ylabel::String,
    scale=identity,
)
    colors = _style!(dark)

    plt = plot(
        title=title,
        xlabel="Number of component types",
        ylabel=ylabel,
        size=(640, 400),
        xlim=(0, maximum(df.N) * 1.03),
        ylim=(0, NaN),
        legend=:topleft,
    )

    for m in MODES
        sub = _series(df, m)
        isempty(sub) && continue
        color = getproperty(colors, m.dispatch)
        plot!(
            sub.N,
            scale.(sub[!, column]),
            label=m.label,
            lw=2.0,
            color=color,
            linestyle=m.style,
            marker=(m.boxed ? :diamond : :circle),
            ms=3.5,
            msc=color,
        )
    end

    savefig(plt, out_file)
    @info "wrote $out_file"
end

# `--plot-only` re-renders the figures from the CSV of a previous sweep, which takes about an
# hour to collect.
const PLOT_ONLY = "--plot-only" in ARGS

df = PLOT_ONLY ? DataFrame(CSV.File(CSV_PATH)) : collect_data()
if !PLOT_ONLY
    CSV.write(CSV_PATH, df)
    @info "wrote $CSV_PATH"
end

mkpath(OUT_DIR)
for (dark, suffix) in ((false, "light"), (true, "dark"))
    plot_metric(
        df, joinpath(OUT_DIR, "bench_erased_compile_$suffix.svg");
        dark=dark, column=:ops,
        title="Compile time of structural operations",
        ylabel="First-call compile time [s]",
    )
    plot_metric(
        df, joinpath(OUT_DIR, "bench_boxed_ctor_$suffix.svg");
        dark=dark, column=:ctor,
        title="Compile time of world construction",
        ylabel="First-call compile time [s]",
    )
    plot_metric(
        df, joinpath(OUT_DIR, "bench_erased_memory_$suffix.svg");
        dark=dark, column=:mem,
        title="Peak process memory",
        ylabel="Peak resident memory [GB]",
        scale=x -> x / 2^30,
    )
end

# Console summary: one block per metric, so the effect each knob has stays visible. `erased`
# shows up in the structural operations, `boxed` in world construction and in memory.
function summarize(df::DataFrame, column::Symbol, title::String, scale=identity)
    println("\n$title")
    @printf("%-6s", "N")
    for m in MODES
        @printf("%18s", m.label)
    end
    println()
    for n in NS
        at_n = filter(r -> r.N == n, df)
        isempty(at_n) && continue
        @printf("%-6d", n)
        for m in MODES
            sub = _series(at_n, m)
            isempty(sub) ? @printf("%18s", "-") : @printf("%18.2f", scale(only(sub)[column]))
        end
        println()
    end
end

summarize(df, :ctor, "World construction compile time [s]")
summarize(df, :ops, "Structural operations compile time [s]")
summarize(df, :mem, "Peak resident memory [GB]", x -> x / 2^30)
