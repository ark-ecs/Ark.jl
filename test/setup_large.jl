
function _storage_from_component(world, comp)
    i = findfirst(x -> first(x.data) isa AbstractArray{comp}, world._storages)
    return typeof(first(world._storages[i].data))
end

function Ark.World(comp_types::Union{Type,Pair{<:Type,<:Type}}...; initial_capacity::Int=128, allow_mutable=false)
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
        if storages[i] == Storage{WrappedVector} && isbitstype(types[i])
            storages[i] = Storage{DiskVector{types[i]}}
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
        Val{Tuple{fake_types[1:255]...,types...,fake_types[256:300]...}}(),
        Val{Tuple{fake_storage[1:255]...,storages...,fake_storage[256:300]...}}(),
        Val{Tuple{relation_types...}}(),
        Val(allow_mutable),
        initial_capacity,
    )
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

struct FakeComp{N} end
const fake_types = [FakeComp{i} for i in 1:300]
const fake_storage = [Storage{WrappedVector} for i in 1:300]
const N_fake = 300
const offset_ID = 255
const M_mask = 5
