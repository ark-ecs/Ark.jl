
struct GrazerDecision <: System end

function initialize!(::GrazerDecision, world::World)
    resource = GrazerDecisionCommands(world)
    @eval global const GrazerDecisionCommandsType = typeof($resource)
    add_resource!(world, resource)
end

function update!(::GrazerDecision, world::World)
    commands = get_resource(world, GrazerDecisionCommandsType).commands
    grass = get_resource(world, GrassGrid).grass[]

    for (entities, positions, genes) in Query(world, (Position, Genes); with=(Moving,))
        for i in eachindex(entities, positions)
            pos = positions[i]
            gene = genes[i]
            cx, cy = floor(Int, pos[1]) + 1, floor(Int, pos[2]) + 1
            grass_here = grass[cx, cy]
            if grass_here > gene.graze_thresh
                exchange_components!(world, commands, entities[i]; add=(Grazing(),), remove=(Moving,))
            end
        end
    end
    for (entities, positions, genes) in Query(world, (Position, Genes); with=(Grazing,))
        for i in eachindex(entities, positions)
            pos = positions[i]
            gene = genes[i]
            cx, cy = floor(Int, pos[1]) + 1, floor(Int, pos[2]) + 1
            grass_here = grass[cx, cy]
            if grass_here < gene.graze_thresh * gene.move_thresh
                exchange_components!(world, commands, entities[i]; add=(Moving(),), remove=(Grazing,))
            end
        end
    end

    apply!(world, commands)
end
