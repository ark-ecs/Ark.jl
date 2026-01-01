
function setup_iterate_vector(n::Int)
    arr = Vector{Position}()
    for i in 1:n
        push!(arr, Position(i, i))
    end
    sum = 0.0
    for pos in arr
        sum += pos.x
    end
    return arr
end

function benchmark_iterate_vector(args, n::Int)
    arr = args
    sum = 0.0
    for pos in arr
        sum += pos.x
    end
    return sum
end

SUITE["benchmark_iterate_vector n=1000"] =
    @be setup_iterate_vector(1000) benchmark_iterate_vector(_, 1000) seconds = SECONDS

function setup_iterate_StructArray(n::Int)
    arr = StructArray(Position)
    for i in 1:n
        push!(arr, Position(i, i))
    end
    sum = 0.0
    for pos in arr
        sum += pos.x
    end
    return arr
end

function benchmark_iterate_StructArray(args, n::Int)
    arr = args
    sum = 0.0
    for pos in arr
        sum += pos.x
    end
    return sum
end

SUITE["benchmark_iterateStructArray n=1000"] =
    @be setup_iterate_StructArray(1000) benchmark_iterate_StructArray(_, 1000) seconds = SECONDS

function setup_iterate_StructArray_view(n::Int)
    arr = StructArray(Position)
    for i in 1:n
        push!(arr, Position(i, i))
    end
    v = view(arr, :)
    sum = 0.0
    for pos in v
        sum += pos.x
    end
    return v
end

function benchmark_iterate_StructArray_view(args, n::Int)
    v = args
    sum = 0.0
    for pos in v
        sum += pos.x
    end
    return sum
end

SUITE["benchmark_iterateStructArray_view n=1000"] =
    @be setup_iterate_StructArray_view(1000) benchmark_iterate_StructArray_view(_, 1000) seconds = SECONDS
