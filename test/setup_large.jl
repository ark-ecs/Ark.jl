
function _storage_from_component(world, comp)
    empties = _storage(world)._empty_storages
    i = findfirst(x -> x isa AbstractArray{comp}, empties)
    return typeof(empties[i])
end

struct WrappedVector{T} <: AbstractVector{T}
    v::Vector{T}
end
WrappedVector{T}() where T = WrappedVector{T}(Vector{T}())

Base.size(w::WrappedVector) = size(w.v)
Base.getindex(w::WrappedVector, i::Integer) = getindex(w.v, i)
Base.setindex!(w::WrappedVector, v, i::Integer) = setindex!(w.v, v, i)
Base.empty!(w::WrappedVector) = empty!(w.v)
Base.resize!(w::WrappedVector, i::Integer) = resize!(w.v, i)
Base.sizehint!(w::WrappedVector, i::Integer) = sizehint!(w.v, i)
Base.pop!(w::WrappedVector) = pop!(w.v)

const WORLD_MODES = (true,)
const DEFAULT_WORLD_BOXED = Ref(first(WORLD_MODES))

struct FakeComp{N} end
const N_fake = 300
const fake_types = [FakeComp{i} for i in 1:N_fake]
const fake_storage = [Storage{WrappedVector} for i in 1:N_fake]
const M_mask = ceil(Int, N_fake / 64)
const offset_ID = (M_mask - 1) * 64 - 1

function TestWorld(
    comp_types::Union{Type,Pair{<:Type,<:Type}}...;
    initial_capacity::Int=128,
    allow_mutable=false,
    boxed::Bool=DEFAULT_WORLD_BOXED[],
)
    raw_types = map(arg -> arg isa Type ? arg : arg.first, comp_types)
    types = map(Ark._unwrap_relation_type, raw_types)
    storages = map(arg -> arg isa Type ? Storage{WrappedVector} : arg.second, comp_types)
    relation_types = map(Ark._unwrap_relation_type, filter(Ark._declares_relation, raw_types))
    storages = collect(Any, storages)
    for i in 1:length(storages)
        if isbitstype(types[i]) && storages[i] == Storage{WrappedVector}
            storages[i] = Storage{GPUVector{:CPU}}
            break
        end
    end
    for i in 1:length(storages)
        if storages[i] == Storage{WrappedVector} && isbitstype(types[i]) && fieldcount(types[i]) > 0
            storages[i] = Storage{DiskVector}
            break
        end
    end
    for i in 1:length(storages)
        if storages[i] == Storage{StructArray}
            storages[i] = Storage{GPUStructArray{:CPU}}
        end
    end
    storages = Tuple(storages)
    Ark._World_from_types(
        Val{Tuple{fake_types[1:offset_ID]...,types...,fake_types[offset_ID+1:N_fake]...}}(),
        Val{Tuple{fake_storage[1:offset_ID]...,storages...,fake_storage[offset_ID+1:N_fake]...}}(),
        Val{Tuple{relation_types...}}(),
        Val(allow_mutable),
        Val(boxed),
        initial_capacity,
    )
end
