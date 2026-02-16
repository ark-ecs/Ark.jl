using Printf

struct Row
    name::String
    n::Int
    time_ns::Float64
    allocs::Int
    bytes::Int
end

struct RowAoS
    name::String
    n::Int
    bytes::Int
    vars::Int
    time_ns::Float64
end

mutable struct CompareRow
    name::String
    n::Int
    time_ns_a::Float64
    time_ns_b::Float64
    factor::Float64
    allocs::Int
    bytes::Int
end

function CompareRow()
    CompareRow("", 0, NaN, NaN, NaN, -1, -1)
end

function trim_prefix(s::String, prefix::String)
    startswith(s, prefix) ? s[(length(prefix)+1):end] : s
end

function write_bench_table(data::Vector{Row}, file::String)
    open(file, "w") do io
        write(io, "Name,N,Time,Allocs,Bytes\n")
        for row in data
            write(io, "$(row.name),$(row.n),$(row.time_ns),$(row.allocs),$(row.bytes)\n")
        end
    end
end

function write_bench_table_aos(data::Vector{RowAoS}, file::String)
    open(file, "w") do io
        write(io, "Name,Bytes,Vars,N,Time\n")
        for row in data
            write(io, "$(row.name),$(row.bytes),$(row.vars),$(row.n),$(row.time_ns)\n")
        end
    end
end

function table_to_csv(data::Vector{CompareRow})::String
    header = "Name,N,Time main,Time curr,Factor"
    body = join([
            "$(row.name),$(row.n),$(row.time_ns_a),$(row.time_ns_b),$(row.factor)"
            for row in data
        ], "\n")
    return header * body
end

function table_to_markdown(data::Vector{CompareRow})::String
    header =
        "| Name                                     |       N | Time main [ns] | Time curr [ns] | Factor |  Allocs |    Bytes |\n" *
        "|:-----------------------------------------|--------:|---------------:|---------------:|-------:|--------:|---------:|\n"

    body = join(
        [
            @sprintf("| %-40s | %7d | %14.2f | %14.2f | %6.2f | %7d | %8d |",
                r.name, r.n, r.time_ns_a, r.time_ns_b, r.factor, r.allocs, r.bytes)
            for r in data
        ], "\n")

    return header * body
end

function table_to_html(data::Vector{CompareRow})::String
    html = """
    <details>
    <summary>Click to expand benchmark results</summary>
    <p>
    Time is per entity/N, allocations are totals.
    Allocations are only shown for current.
    </p>
    <table>
      <thead>
        <tr>
          <th align="center">N</th>
          <th align="center">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Time main&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
          <th align="center">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Time curr&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
          <th align="center">&nbsp;&nbsp;&nbsp;&nbsp;Factor&nbsp;&nbsp;&nbsp;&nbsp;</th>
          <th align="center">&nbsp;&nbsp;&nbsp;&nbsp;Allocs&nbsp;&nbsp;&nbsp;&nbsp;</th>
          <th align="center">&nbsp;&nbsp;&nbsp;&nbsp;Bytes&nbsp;&nbsp;&nbsp;&nbsp;</th>
        </tr>
      </thead>
      <tbody>
    """

    improved = 0
    regressed = 0

    name = ""
    for r in data
        emoji = ""
        if r.factor <= 0.9
            improved += 1
            emoji = "🚀"
        elseif r.factor >= 1.1
            regressed += 1
            emoji = "⚠️"
        end

        if name != r.name
            name_short = trim_prefix(r.name, "benchmark_")
            html *= @sprintf("""<tr><th colspan="6" align="center">%s</th></tr>\n""", name_short)
        end

        html *= @sprintf("""
            <tr>
            <td align="right">%d</td>
            <td align="right">%.2fns</td>
            <td align="right">%.2fns</td>
            <td align="right">%s %.2f</td>
            <td align="right">%d</td>
            <td align="right">%d</td>
            </tr>
            """, r.n, r.time_ns_a, r.time_ns_b, emoji, r.factor, r.allocs, r.bytes)

        name = r.name
    end

    html *= """
      </tbody>
    </table>
    </details>
    """

    if regressed == 0 && improved == 0
        html = "<p>✅ Benchmarks are stable!</p>" * "\n" * html
    else
        if regressed > 0
            html = "<p>⚠️ $(regressed) benchmark regressions detected!</p>" * "\n" * html
        end
        if improved > 0
            html = "<p>🚀 $(improved) benchmark improvements detected!</p>" * "\n" * html
        end
    end

    return html
end

function read_bench_table(file::String)::Vector{Row}
    data = Vector{Row}()
    open(file, "r") do io
        for line in Iterators.drop(eachline(io), 1)
            parts = split(line, ",")
            push!(
                data,
                Row(
                    parts[1],
                    parse(Int, parts[2]),
                    parse(Float64, parts[3]),
                    parse(Int, parts[4]),
                    parse(Int, parts[5]),
                ),
            )
        end
    end
    return data
end

function compare_multi_tables(a::Vector{Vector{Row}}, b::Vector{Vector{Row}})::Vector{CompareRow}
    compare_multi = [compare_tables(a, b) for (a, b) in zip(a, b)]

    count = length(compare_multi)
    data = Vector{CompareRow}()
    for r in eachindex(compare_multi[1])
        out::CompareRow = CompareRow("", 0, 0, 0, 0, 0, 0)
        for t in compare_multi
            row = t[r]
            out.name = row.name
            out.n = row.n
            out.time_ns_a += row.time_ns_a
            out.time_ns_b += row.time_ns_b
            out.factor += row.factor
            out.allocs += row.allocs
            out.bytes += row.bytes
        end
        out.time_ns_a /= count
        out.time_ns_b /= count
        out.factor /= count
        out.allocs /= count
        out.bytes /= count
        push!(data, out)
    end

    return data
end

thaskey(dict::Dict, key) = haskey(dict, key)

function compare_tables(a::Vector{Row}, b::Vector{Row})::Vector{CompareRow}
    dict_a = Dict(@sprintf("%s %07d", x.name, x.n) => x for x in a)
    dict_b = Dict(@sprintf("%s %07d", x.name, x.n) => x for x in b)

    keys_set = Set{String}()

    for k in keys(dict_a)
        push!(keys_set, k)
    end
    for k in keys(dict_b)
        push!(keys_set, k)
    end
    keys_vec = sort(collect(keys_set))
    data = Vector{CompareRow}()

    for bench in keys_vec
        row = CompareRow()
        if thaskey(dict_a, bench)
            r = dict_a[bench]
            row.name = r.name
            row.n = r.n
            row.time_ns_a = r.time_ns
        end
        if thaskey(dict_b, bench)
            r = dict_b[bench]
            row.name = r.name
            row.n = r.n
            row.time_ns_b = r.time_ns
            row.allocs = r.allocs
            row.bytes = r.bytes
        end
        row.factor = row.time_ns_b / row.time_ns_a
        push!(data, row)
    end

    return data
end
