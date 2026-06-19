
struct GrazerMortality <: System end

function initialize!(::GrazerMortality, world::World)
    add_resource!(world, GrazerMortalityCommands(world))
end

function update!(::GrazerMortality, world::World)
    commands = get_resource(world, GrazerMortalityCommandsType).commands

    for (entities, energies) in Query(world, (Energy,))
        for i in eachindex(entities, energies)
            if energies[i].value <= 0
                remove_entity!(world, commands, entities[i])
            end
        end
    end

    apply!(world, commands)
end
