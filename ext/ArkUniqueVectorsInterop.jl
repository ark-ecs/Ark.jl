module ArkUniqueVectorsInterop

using Ark, UniqueVectors

function Ark._swap!(v::UniqueVector, i, j)
    moved = @inbounds v[j]
    UniqueVectors.swap!(v, Int(i), Int(j))
    return moved
end

function Ark._swap_indices!(v::UniqueVector, i, j)
    UniqueVectors.swap!(v, Int(i), Int(j))
    return
end

end
