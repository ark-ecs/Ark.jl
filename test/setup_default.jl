
function _storage_from_component(world, comp)
    empties = _storage(world)._empty_storages
    i = findfirst(x -> x isa AbstractArray{comp}, empties)
    return typeof(empties[i])
end

const WORLD_MODES = (true, false)
const DEFAULT_WORLD_BOXED = Ref(first(WORLD_MODES))

function TestWorld(
    comp_types::Union{Type,Pair{<:Type,<:Type}}...;
    initial_capacity::Int=16,
    allow_mutable=false,
    boxed::Bool=DEFAULT_WORLD_BOXED[],
)
    return World(
        comp_types...;
        initial_capacity=initial_capacity,
        allow_mutable=allow_mutable,
        boxed=boxed,
    )
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
