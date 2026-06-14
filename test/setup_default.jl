
function _storage_from_component(world, comp)
    i = findfirst(x -> Ark._component_type(typeof(x)) == comp, _storage(world)._storages)
    return Ark._storage_array_type(typeof(_storage(world)._storages[i]))
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
