
function _storage_from_component(world, comp)
    empties = _storage(world)._empty_storages
    i = findfirst(x -> x isa AbstractArray{comp}, empties)
    return typeof(empties[i])
end

# The suite is run once per entry of `WORLD_MODES`. `TestWorld` calls without an explicit
# `mode` pick up the mode of the current pass, so every test covers every mode.
const WORLD_MODES = (:boxed, :specialized)
const DEFAULT_WORLD_MODE = Ref(first(WORLD_MODES))

function TestWorld(
    comp_types::Union{Type,Pair{<:Type,<:Type}}...;
    initial_capacity::Int=16,
    allow_mutable=false,
    mode::Symbol=DEFAULT_WORLD_MODE[],
)
    return World(
        comp_types...;
        initial_capacity=initial_capacity,
        allow_mutable=allow_mutable,
        mode=mode,
    )
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
