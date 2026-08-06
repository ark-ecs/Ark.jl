include("util/compare.jl")

# Usage: compare_benchmarks.jl [repetitions] [boxed value...]
#
# With no arguments this compares `bench_{main,current}_$i.csv` for i in 1:3 and emits a
# single unlabelled section, which is what the internal benchmark workflow expects.
#
# Given a repetition count and one or more `boxed` values it instead reads
# `bench_{main,current}_$(boxed)_$i.csv` and emits one labelled section per value, so that
# a single PR comment reports each world mode separately.
const REPS = isempty(ARGS) ? 3 : parse(Int, ARGS[1])
const BOXED_VALUES = length(ARGS) > 1 ? ARGS[2:end] : String[]

function compare_variant(boxed::String)
    tag = isempty(boxed) ? "" : "_$boxed"
    data_current = [read_bench_table("bench_current$(tag)_$(i).csv") for i in 1:REPS]
    data_main = [read_bench_table("bench_main$(tag)_$(i).csv") for i in 1:REPS]
    return compare_multi_tables(data_main, data_current)
end

function main()
    if isempty(BOXED_VALUES)
        result = compare_variant("")
        write("compare.csv", table_to_csv(result))
        write("compare.html", table_to_html(result))
        println(table_to_markdown(result))
        return nothing
    end

    html = ""
    markdown = ""
    for boxed in BOXED_VALUES
        result = compare_variant(boxed)
        write("compare_boxed_$(boxed).csv", table_to_csv(result))
        html *= "<h3>boxed = $boxed</h3>\n" * table_to_html(result) * "\n"
        markdown *= "## boxed = $boxed\n\n" * table_to_markdown(result) * "\n\n"
    end
    write("compare.html", html)
    println(markdown)
    return nothing
end

main()
