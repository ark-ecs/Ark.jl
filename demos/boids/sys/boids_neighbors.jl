
struct BoidsNeighbors <: System
    max_distance::Int
end

BoidsNeighbors(;
    max_distance::Int,
) = BoidsNeighbors(max_distance)

function initialize!(s::BoidsNeighbors, world::World)
    size = get_resource(world, WorldSize)
    add_resource!(world, Grid(size.width, size.height, s.max_distance))
end

function update!(s::BoidsNeighbors, world::World)
    tick = get_resource(world, Tick).tick
    grid = get_resource(world, Grid)
    max_dist_sq = Float64(s.max_distance * s.max_distance)

    for i in 1:grid.rows, j in 1:grid.cols
        resize!(grid.entities[i, j], 0)
    end

    for (entities, positions) in Query(world, (Position,))
        for i in eachindex(entities, positions)
            row, col = cell(grid, positions[i].p)
            push!(grid.entities[row, col], entities[i])
        end
    end

    for (entities1, positions1, neighbors, updates) in Query(world, (Position, Neighbors, UpdateStep))
        for i in eachindex(positions1, neighbors, updates)
            if tick % 30 != updates[i].step
                continue
            end
            pos1 = positions1[i]
            entity1 = entities1[i]
            neigh = neighbors[i]
            resize!(neigh.n, 0)

            row, col = cell(grid, pos1.p)

            for r in max(row-1, 1):min(row+1, grid.rows), c in max(col-1, 1):min(col+1, grid.cols)
                candidates = grid.entities[r, c]
                for entity2 in candidates
                    if entity1 == entity2
                        continue
                    end
                    pos2, = get_components(world, entity2, (Position,))
                    if distance_sq(pos1.p, pos2.p) <= max_dist_sq
                        push!(neigh.n, entity2)
                    end
                end
            end
        end
    end
end
