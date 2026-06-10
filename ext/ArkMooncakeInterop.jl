
module ArkMooncakeInterop

using Ark, Mooncake, Mooncake.Random

Mooncake.tangent_type(::Type{<:Ark._GraphNode}) = Mooncake.NoTangent
Mooncake.tangent_type(::Type{<:Ark._VecMap}) = Mooncake.NoTangent
Mooncake.@mooncake_overlay function _observer_show_strings(
    comps::_Mask{M},
    with::_Mask{M},
    without::_Mask{M},
    is_exclusive::Bool,
    ::Type{W},
) where {M,W<:_AbstractWorld}
    return "", "", ""
end

end
