
function _storage_from_component(world, comp)
    i = findfirst(x -> first(x.data) isa AbstractArray{comp}, _storage(world)._storages)
    return typeof(first(_storage(world)._storages[i].data))
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
