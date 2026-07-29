
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
const N_ENTITIES = 10_000

const MODES = (
    (mode="specialized", label="specialized", color=:specialized, style=:solid, marker=:circle),
    (mode="boxed", label="boxed", color=:boxed, style=:solid, marker=:diamond),
)

const OUT_DIR = joinpath(REPO, "docs", "src", "assets", "images")
const CSV_PATH = joinpath(HERE, "compile_time.csv")
const PARTIAL_CSV_PATH = joinpath(HERE, "compile_time.partial.csv")
const WORKER_TIMEOUT = 30 * 60

# Compiling the `:specialized` switches costs C stack roughly linearly in the number of
# component types - measured peak stack is 1.2MB at N=500, 8.5MB at N=2500, 11.7MB at N=3000,
# about 7kB per component. That crosses the usual 8MB soft limit somewhere around N=2400.
# therefore get a stack large enough that the curve ends where compilation actually stops
# being viable rather than where `ulimit` does.
const WORKER_STACK_KB = 65536

function with_stack_limit(cmd::Cmd)
    Sys.isunix() || return cmd
    script = "ulimit -s $WORKER_STACK_KB 2>/dev/null || true; exec $(Base.shell_escape_posixly(cmd))"
    return `sh -c $script`
end

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
        specialized=dark ? "#e74c3c" : "#c0392b",
        boxed=dark ? "#1abc9c" : "#2e63b8",
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

const PLOT_ONLY = "--plot-only" in ARGS

df = PLOT_ONLY ? DataFrame(CSV.File(CSV_PATH)) : collect_data()
if !PLOT_ONLY
    CSV.write(CSV_PATH, df)
    rm(PARTIAL_CSV_PATH, force=true)
    @info "wrote $CSV_PATH"
end

mkpath(OUT_DIR)
for (dark, suffix) in ((false, "light"), (true, "dark"))
    plot_metric(
        df, joinpath(OUT_DIR, "bench_boxed_compile_$suffix.svg");
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
        df, joinpath(OUT_DIR, "bench_boxed_memory_$suffix.svg");
        dark=dark, column=:mem,
        title="Peak process memory",
        ylabel="Peak resident memory [GB]",
        scale=x -> x / 2^30,
    )
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
