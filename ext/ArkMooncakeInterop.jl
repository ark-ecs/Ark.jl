
module ArkMooncakeInterop

using Ark, Mooncake

Mooncake.tangent_type(::Type{<:Ark._GraphNode}) = Mooncake.NoTangent

Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent

Mooncake.@zero_adjoint Mooncake.DefaultCtx Tuple{
    typeof(Ark._observer_show_strings),
    Ark._Mask{M},
    Ark._Mask{M},
    Ark._Mask{M},
    Bool,
    Type{W},
} where {M,W<:Ark._AbstractWorld}

end
