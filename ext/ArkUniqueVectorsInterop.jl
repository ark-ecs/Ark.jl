module ArkUniqueVectorsInterop

using Ark, UniqueVectors

Ark._swap!(v::UniqueVector, i, j) = swapat!(v, i, j)

end
