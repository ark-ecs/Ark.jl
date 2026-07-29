# Driver: sweeps the number of component types, measures first-call compile time of the three
# world modes at each point (one fresh worker process per point, so every measurement is a
# cold compile), writes a CSV, and renders the light/dark figures used in the docs.
#
# The world modes form a ladder of how much code Ark generates per component type:
# `:monomorphic` emits a specialized copy of every structural operation, `:erased` keeps only
# a generated storage selection, `:boxed` keeps none at all. The steps show up in different
# columns - erasing the operations in their compile time, boxing the storages in the cost of
# world construction and in memory - which is why all three are plotted.
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
# Entities per runtime sample. Passed to the worker so the number lives in one place and the
# plot labels cannot drift from what was actually measured.
const N_ENTITIES = 10_000

# The three world modes. Colour separates monomorphic from erased dispatch, line style marks
# the boxed storages on top of it, so each step of the ladder stays readable.
const MODES = (
    (mode="monomorphic", label="monomorphic", color=:monomorphic, style=:solid, marker=:circle),
    (mode="erased", label="erased", color=:erased, style=:solid, marker=:circle),
    (mode="boxed", label="boxed", color=:erased, style=:dash, marker=:diamond),
)

const OUT_DIR = joinpath(REPO, "docs", "src", "assets", "images")
const CSV_PATH = joinpath(HERE, "compile_time.csv")
# Checkpoint of a sweep in progress. Kept apart from `CSV_PATH` so an interrupted run never
# overwrites the results of a completed one; only a sweep that reaches the end promotes.
const PARTIAL_CSV_PATH = joinpath(HERE, "compile_time.partial.csv")

# A worker that overflows the compiler's stack does not always die: Julia prints its
# "detected a stack overflow" warning and the process can wedge instead of exiting, at which
# point reading its output blocks forever and the sweep stalls. Generous enough that a real
# measurement is never cut short - the slowest legitimate point so far is `:monomorphic` at
# N=3000, about eight minutes of compilation - and short enough that a wedge does not cost an
# afternoon.
const WORKER_TIMEOUT = 30 * 60

# Compiling the `:monomorphic` switches costs C stack roughly linearly in the number of
# component types - measured peak stack is 1.2MB at N=500, 8.5MB at N=2500, 11.7MB at N=3000,
# about 7kB per component. That crosses the usual 8MB soft limit somewhere around N=2400,
# which makes the sweep unreliable long before it is genuinely out of road: N=2000 and N=2500
# both pass or wedge depending on the run. Workers therefore get a stack large enough that the
# curve ends where compilation actually stops being viable rather than where `ulimit` does.
const WORKER_STACK_KB = 65536

# Wraps a worker command so it runs under a raised stack soft limit. `ulimit` is a shell
# builtin and the limit is inherited across `exec`, so this is the portable way to set it for
# a child process; raising the soft limit toward the (usually unlimited) hard limit needs no
# privileges. Left alone on non-unix, where the sweep is not expected to run anyway.
function with_stack_limit(cmd::Cmd)
    Sys.isunix() || return cmd
    script = "ulimit -s $WORKER_STACK_KB 2>/dev/null || true; exec $(Base.shell_escape_posixly(cmd))"
    return `sh -c $script`
end

# Runs one worker, returning its stdout. Throws if it exits non-zero, or if it has to be
# killed for exceeding `WORKER_TIMEOUT`; either way the caller drops the mode.
function run_worker(cmd::Cmd)
    out = Base.BufferStream()
    proc = run(pipeline(with_stack_limit(cmd), stdout=out), wait=false)
    watchdog = Timer(WORKER_TIMEOUT) do _
        process_running(proc) && kill(proc, Base.SIGKILL)
    end
    try
        wait(proc)
    finally
        close(watchdog)
        close(out)
    end
    text = read(out, String)
    success(proc) ||
        error("worker exited with code $(proc.exitcode), signal $(proc.termsignal)")
    return text
end

function collect_data()
    rows = NamedTuple{
        (:N, :mode, :ctor, :ops, :mem, :rt_cold, :rt_steady),
        Tuple{Int,String,Float64,Float64,Float64,Float64,Float64},
    }[]
    # A mode that has already taken a worker down is dropped from the rest of the sweep. Past
    # a few thousand component types `:monomorphic` emits one branch per component in every
    # structural operation, and compiling that overflows the compiler's own stack - the worker
    # either dies with "detected a stack overflow" or wedges and is killed by the watchdog.
    # That is the wall the erased modes exist to remove, so it is a result rather than a
    # failure; the point is just missing from the plot. Retrying the same mode at a larger N
    # would only burn half an hour to die again.
    failed = Set{String}()
    for n in NS
        for m in MODES
            if m.mode in failed
                @info "skipping N=$n, mode=$(m.mode): mode already failed at a smaller N"
                continue
            end
            @info "measuring N=$n, mode=$(m.mode)"
            out = try
                run_worker(`$JULIA --project=$PROJECT $WORKER $n $K_SITES $(m.mode) $N_ENTITIES`)
            catch err
                err isa InterruptException && rethrow()
                @warn "worker failed, dropping this mode from the rest of the sweep" N = n mode = m.mode exception =
                    err
                push!(failed, m.mode)
                continue
            end
            for line in split(strip(out), '\n')
                isempty(line) && continue
                n_s, mode_s, ctor_s, ops_s, mem_s, cold_s, steady_s = split(line, ',')
                push!(rows, (N=parse(Int, n_s), mode=String(mode_s),
                    ctor=parse(Float64, ctor_s), ops=parse(Float64, ops_s),
                    mem=parse(Float64, mem_s), rt_cold=parse(Float64, cold_s),
                    rt_steady=parse(Float64, steady_s)))
            end
        end
        println(DataFrame(rows))
        # The sweep takes about an hour and the large-N points are the ones that can take the
        # driver down with them, so checkpoint after every N. This deliberately goes to its own
        # file rather than to `CSV_PATH`: a run that is interrupted, or cut short for a quick
        # check, must not leave a stub where a previous complete sweep used to be.
        isempty(rows) || CSV.write(PARTIAL_CSV_PATH, DataFrame(rows))
    end
    return DataFrame(rows)
end

_series(df::DataFrame, m) = sort(filter(r -> r.mode == m.mode, df), :N)

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
        monomorphic=dark ? "#e74c3c" : "#c0392b",
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
    logscale::Bool=false,
)
    colors = _style!(dark)

    plt = plot(
        title=title,
        xlabel="Number of component types",
        ylabel=logscale ? "$ylabel, log scale" : ylabel,
        size=(640, 400),
        xlim=(0, maximum(df.N) * 1.03),
        # A log axis cannot contain zero, so the lower bound is left to the data there.
        ylim=logscale ? :auto : (0, NaN),
        yscale=logscale ? :log10 : :identity,
        minorgrid=logscale,
        legend=:topleft,
    )

    for m in MODES
        sub = _series(df, m)
        isempty(sub) && continue
        color = getproperty(colors, m.color)
        plot!(
            sub.N,
            scale.(sub[!, column]),
            label=m.label,
            lw=2.0,
            color=color,
            linestyle=m.style,
            marker=m.marker,
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
    # Only a sweep that ran to the end promotes its checkpoint to the real CSV.
    CSV.write(CSV_PATH, df)
    rm(PARTIAL_CSV_PATH, force=true)
    @info "wrote $CSV_PATH"
end

mkpath(OUT_DIR)
for (dark, suffix) in ((false, "light"), (true, "dark"))
    plot_metric(
        df, joinpath(OUT_DIR, "bench_erased_compile_$suffix.svg");
        dark=dark, column=:ops,
        title="Compile time of structural operations",
        ylabel="First-call compile time [s]",
        logscale=true,
    )
    plot_metric(
        df, joinpath(OUT_DIR, "bench_boxed_ctor_$suffix.svg");
        dark=dark, column=:ctor,
        title="Compile time of world construction",
        ylabel="First-call compile time [s]",
        logscale=true,
    )
    plot_metric(
        df, joinpath(OUT_DIR, "bench_erased_memory_$suffix.svg");
        dark=dark, column=:mem,
        title="Peak process memory",
        ylabel="Peak resident memory [GB]",
        scale=x -> x / 2^30,
    )
    # Linear, unlike the compile-time plots: these span a fraction of a decade, where a log
    # axis only buys tick labels like 10^-0.15. Add `logscale=true` if the spread ever grows.
    plot_metric(
        df, joinpath(OUT_DIR, "bench_runtime_cold_$suffix.svg");
        dark=dark, column=:rt_cold,
        title="Runtime of structural operations, growing world",
        ylabel="Time for $(N_ENTITIES) entities [ms]",
        scale=x -> x * 1e3,
    )
    plot_metric(
        df, joinpath(OUT_DIR, "bench_runtime_steady_$suffix.svg");
        dark=dark, column=:rt_steady,
        title="Runtime of structural operations, steady state",
        ylabel="Time for $(N_ENTITIES) entities [ms]",
        scale=x -> x * 1e3,
    )
end

# Console summary: one block per metric, so what each step of the ladder buys stays visible.
# Erasing the operations shows up in the structural operations, boxing the storages on top of
# that shows up in world construction and in memory.
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
summarize(df, :rt_cold, "Structural operations runtime, growing world [ms/$(N_ENTITIES) entities]", x -> x * 1e3)
summarize(df, :rt_steady, "Structural operations runtime, steady state [ms/$(N_ENTITIES) entities]", x -> x * 1e3)
