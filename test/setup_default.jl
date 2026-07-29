
function _storage_from_component(world, comp)
    empties = world._empty_storages
    i = findfirst(x -> x isa AbstractArray{comp}, empties)
    return typeof(empties[i])
end

# The suite is run once per entry of `WORLD_MODES`. Worlds built without an explicit
# `mode` pick up the mode of the current pass, so every test covers every mode.
const WORLD_MODES = (:specialized, :boxed)
const DEFAULT_WORLD_MODE = Ref(first(WORLD_MODES))

function Ark.World(
    comp_types::Union{Type,Pair{<:Type,<:Type}}...;
    initial_capacity::Int=16,
    allow_mutable=false,
    mode::Symbol=DEFAULT_WORLD_MODE[],
)
    raw_types = map(arg -> arg isa Type ? arg : arg.first, comp_types)
    types = map(Ark._unwrap_relation_type, raw_types)
    storages = map(arg -> arg isa Type ? Storage{Vector} : arg.second, comp_types)
    relation_types = map(Ark._unwrap_relation_type, filter(Ark._declares_relation, raw_types))
    Ark._World_from_types(
        Val{Tuple{types...}}(),
        Val{Tuple{storages...}}(),
        Val{Tuple{relation_types...}}(),
        Val(allow_mutable),
        Val(Ark._mode_boxed(mode)),
        initial_capacity,
    )
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
