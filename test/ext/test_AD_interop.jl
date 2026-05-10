
using DifferentiationInterface
using FiniteDiff
using FiniteDifferences
using ForwardDiff
using GTPSA
using Mooncake
using PolyesterForwardDiff
using ReverseDiff

@testset "Compute gradients through DifferentiationInterface backends" begin
    function run_world(args::AbstractVector{T}) where {T<:Number}
        alpha, beta = args
        world = World(Position{T}, Velocity{T}, ChildOf)
        relation_total = Ref(zero(alpha + beta))

        function accumulate_position!(accum, entity)
            if has_components(world, entity, (Position{T},))
                pos, = get_components(world, entity, (Position{T},))
                accum[] += pos.x + pos.y
            end
            return nothing
        end

        function accumulate_relation_state!(entity, target)
            accumulate_position!(relation_total, entity)
            if target == zero_entity
                pos, = get_components(world, entity, (Position{T},))
                relation_total[] += pos.x - pos.y
            else
                accumulate_position!(relation_total, target)
            end
            return nothing
        end

        entities = Entity[]
        sizehint!(entities, 100)
        for i in 1:100
            entity = new_entity!(world, (Position{T}(T(i), T(i * 2)),))
            push!(entities, entity)
        end

        for e in entities
            add_components!(world, e, (Velocity{T}(one(T), one(T)),))
        end

        added_relations = 0
        removed_relations = 0
        removed_entities = 0

        observe!(world, OnAddRelations, (ChildOf,)) do entity
            get_relations(world, entity, (ChildOf,))
            added_relations += 1
            return nothing
        end

        observe!(world, OnRemoveRelations, (ChildOf,)) do entity
            get_relations(world, entity, (ChildOf,))
            removed_relations += 1
            return nothing
        end

        observe!(world, OnRemoveEntity) do entity
            removed_entities += 1
            return nothing
        end

        parent1 = new_entity!(world, (Position{T}(alpha + one(T), beta + one(T)),))
        parent2 = new_entity!(world, (Position{T}(alpha + beta, alpha - beta),))
        child = new_entity!(world, (Position{T}(alpha, beta), ChildOf() => parent1))

        relation, = get_relations(world, child, (ChildOf,))
        accumulate_relation_state!(child, relation)

        set_relations!(world, child, (ChildOf => parent2,))
        relation, = get_relations(world, child, (ChildOf,))
        accumulate_relation_state!(child, relation)

        remove_entity!(world, parent2)
        relation, = get_relations(world, child, (ChildOf,))
        accumulate_relation_state!(child, relation)

        remove_entity!(world, child)

        for e in entities
            pos, vel = get_components(world, e, (Position{T}, Velocity{T}))
            world[e][Position{T}] = Position{T}(pos.x + alpha, pos.y + beta)
            world[e][Velocity{T}] = Velocity{T}(vel.dx + alpha, vel.dy + beta)
        end

        for e in entities
            ce = copy_entity!(world, e; remove=(Velocity{T},))
            add_components!(world, ce, (Velocity{T}(one(T) + beta, one(T) + alpha),))

            cpos, cvel = get_components(world, ce, (Position{T}, Velocity{T}))
            set_components!(world, ce, (Position{T}(cpos.x + cvel.dx, cpos.y + cvel.dy),))
        end

        for _ in 1:10
            for (entities, positions, velocities) in Query(world, (Position{T}, Velocity{T}))
                @inbounds for i in eachindex(entities)
                    pos = positions[i]
                    vel = velocities[i]
                    positions[i] = Position{T}(alpha * (pos.x + vel.dx), beta * (pos.y + vel.dy))
                end
            end
        end

        total = zero(alpha + beta)
        for (entities, positions) in Query(world, (Position{T},))
            @inbounds for pos in positions
                total += pos.x + pos.y
            end
        end

        observer_total = (alpha + beta) * added_relations
        observer_total += alpha * removed_relations
        observer_total += beta * removed_entities

        return total + relation_total[] + observer_total
    end

    function gradient_ratios(backend)
        delta = 10e-5
        point = [0.1, 0.5]
        base = run_world(point)
        d_alpha, d_beta = DifferentiationInterface.gradient(run_world, backend, point)

        return (
            alpha=(run_world([0.1 + delta, 0.5]) - base) / (d_alpha * delta),
            beta=(run_world([0.1, 0.5 + delta]) - base) / (d_beta * delta),
        )
    end

    @testset "Supported backends" begin
        for (name, backend) in (
            ("Mooncake", AutoMooncake()),
            ("MooncakeForward", AutoMooncakeForward()),
            ("FiniteDiff", AutoFiniteDiff()),
            ("FiniteDifferences", AutoFiniteDifferences(fdm=FiniteDifferences.central_fdm(5, 1))),
            ("ForwardDiff", AutoForwardDiff()),
            ("GTPSA", AutoGTPSA()),
            ("PolyesterForwardDiff", AutoPolyesterForwardDiff()),
            ("ReverseDiff", AutoReverseDiff()),
        )
            @testset "$name" begin
                time = @elapsed ratios = gradient_ratios(backend)
                @test 0.99 < ratios.alpha < 1.01
                @test 0.99 < ratios.beta < 1.01
                println("Gradient TTFX with $name: $time s")
                time = @elapsed ratios = gradient_ratios(backend)
                println("Gradient RunTime with $name: $time s")
            end
        end
    end
end
