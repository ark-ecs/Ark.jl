
module ArkMooncakeInterop

using Ark, Mooncake

Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent

end
