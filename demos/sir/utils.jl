
function rate_to_probability(r::T, t::T) where {T<:AbstractFloat}
    1 - exp(-r * t)
end

function get_count(world, ::Type{T}) where {T<:HealthState}
    q = Query(world, (), with=(T,))
    count = count_entities(world, q)
    close!(q)
    return count
end
