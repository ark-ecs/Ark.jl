
using BenchmarkTools

function process_benches(suite::BenchmarkGroup)::Vector{Row}
    data = Vector{Row}()
    sorted_keys = sort(collect(keys(suite)))

    for name in sorted_keys
        bench = suite[name]
        parts = split(name, " n=")
        n = parse(Int, parts[end])
        mean_secs = median(map(s -> s.time, bench.samples))
        ns_per_n = 1e9 * mean_secs / n

        total_allocs = median(map(s -> s.allocs, bench.samples))
        total_bytes = median(map(s -> s.bytes, bench.samples))
        push!(data, Row(parts[1], n, ns_per_n, total_allocs, total_bytes))
    end

    return data
end

function process_benches_aos(suite::BenchmarkGroup)::Vector{RowAoS}
    data = Vector{RowAoS}()
    sorted_keys = sort(collect(keys(suite)))

    for name in sorted_keys
        bench = suite[name]
        parts = split(name, " n=")
        n = parse(Int, parts[end])
        parts = split(parts[1], " bytes=")
        bytes = parse(Int, parts[end])
        mean_secs = median(map(s -> s.time, bench.samples))
        ns_per_n = 1e9 * mean_secs / n
        push!(data, RowAoS(parts[1], n, bytes, bytes / 8, ns_per_n))
    end

    return data
end
