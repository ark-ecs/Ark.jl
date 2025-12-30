
function Ark.World(comp_types::Union{Type,Pair{<:Type,<:Type}}...; initial_capacity::Int=128, allow_mutable=false)
    types = map(arg -> arg isa Type ? arg : arg.first, comp_types)
    storages = map(arg -> arg isa Type ? VectorStorage : arg.second, comp_types)
    Ark._World_from_types(
        Val{Tuple{fake_types[1:255]...,types...,fake_types[256:300]...}}(),
        Val{Tuple{fake_storage[1:255]...,storages...,fake_storage[256:300]...}}(),
        Val(allow_mutable),
        initial_capacity,
    )
end

struct FakeComp{N} end
const fake_types = [FakeComp{i} for i in 1:300]
const fake_storage = [VectorStorage for i in 1:300]
const N_fake = 300
const offset_ID = 255
const M_mask = 5
