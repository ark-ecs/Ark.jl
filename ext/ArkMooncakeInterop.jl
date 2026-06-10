
module ArkMooncakeInterop

using Ark, Mooncake, Mooncake.Random

Mooncake.tangent_type(::Type{<:Ark._GraphNode}) = Mooncake.NoTangent

Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent

Mooncake.@mooncake_overlay function _observer_show_strings(
    comps::Ark._Mask{M},
    with::Ark._Mask{M},
    without::Ark._Mask{M},
    is_exclusive::Bool,
    ::Type{W},
) where {M,W<:Ark._AbstractWorld}
    return "", "", ""
end

end
