
function _storage_from_component(world, comp)
    empties = _storage(world)._empty_storages
    i = findfirst(x -> x isa AbstractArray{comp}, empties)
    return typeof(empties[i])
end

const N_fake = 0
const offset_ID = 0
const M_mask = 1
