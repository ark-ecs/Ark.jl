
module ArkMooncakeInterop

using Ark, Mooncake, Mooncake.Random

Mooncake.tangent_type(::Type{<:Ark._GraphNode}) = Mooncake.NoTangent
Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent
Mooncake.tangent_type(::Type{<:Ark._EventManager}) = Mooncake.NoTangent

end
