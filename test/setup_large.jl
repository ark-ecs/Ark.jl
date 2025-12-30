
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
fake_types = [FakeComp{i} for i in 1:300]
fake_storage = [VectorStorage for i in 1:300]
N_fake = 300
offset_ID = 255
M_mask = 5
