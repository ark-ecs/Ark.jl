struct _ComponentIndex{M}
    archetypes::Memory{Vector{_Archetype{M}}}
    archetypes_hot::Memory{Vector{_ArchetypeHot{M}}}
end

function _ComponentIndex{M}(components::Int) where M
    return _ComponentIndex(
        Memory{Vector{_Archetype{M}}}([Vector{_Archetype{M}}() for _ in 1:components]),
        Memory{Vector{_ArchetypeHot{M}}}([Vector{_ArchetypeHot{M}}() for _ in 1:components]),
    )
end
