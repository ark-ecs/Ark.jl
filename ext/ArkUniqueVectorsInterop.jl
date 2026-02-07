module ArkUniqueVectorsInterop

using Ark, UniqueVectors

Ark._swap!(v::UniqueVector, i, j) = swapat!(v, i, j)

function Ark._swap_indices!(v::UniqueVector, i, j)
    swapat!(v, i, j)
    return
end

end
