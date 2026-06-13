
module ArkMooncakeInterop

using Ark, Mooncake

Mooncake.tangent_type(::Type{<:Ark._GraphNode}) = Mooncake.NoTangent

Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent

end
