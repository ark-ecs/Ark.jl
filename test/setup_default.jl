
function _storage_from_component(world, comp)
    i = findfirst(x -> x.empty_column isa AbstractArray{comp}, _storage(world)._storages)
    return typeof(_storage(world)._storages[i].empty_column)
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
