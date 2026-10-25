
using PrecompileTools

@setup_workload let
    struct A
        x::Float64
    end
    struct B
        x::Float64
    end
    struct C end
    @compile_workload _world_type_params(ntuple(_ -> A, 40))
    for boxed in (true, false)
        # world with relations
        @compile_workload let
            w = World(A, B => Storage{StructArray}, Relation{C}; boxed=boxed)
            e1 = new_entity!(w, (A(0.0), B(0.0)))
            e2 = new_entity!(w, (A(0.0), B(0.0), C() => e1))
            e3 = copy_entity!(w, e1)
            es = Entity[]
            evs = (OnAddComponents, OnRemoveComponents)
            for ev in evs
                for t in ((A,), (B,), (C,), (A, B), (A, C), (B, C), (A, B, C))
                    observe!(e -> push!(es, e), w, ev, t)
                end
            end
            evs2 = (OnCreateEntity, OnRemoveEntity)
            for ev in evs2
                observe!(e -> push!(es, e), w, ev)
            end
            evs3 = (OnAddRelations, OnRemoveRelations)
            for ev in evs3
                observe!(e -> push!(es, e), w, ev, (C,))
            end
            has_components(w, e2, (A, B, C)) && collect(Query(w, (A, B)))
            collect(Query(w, (A, B, C)))
            a, b, c = get_components(w, e2, (A, B, C))
            set_components!(w, e2, (A(a.x + 1.0), B(b.x + 1.0), c))
            remove_components!(w, e2, (A, C))
            add_components!(w, e2, (A(0.0), C() => e1))
            e1, = get_relations(w, e2, (C,))
            add_components!(w, e3, (C() => e2,))
            set_relations!(w, e3, (C => e1,))
            copy_entity!(w, e3; mode=:ref)
            copy_entity!(w, e3; mode=:deepcopy)
            remove_entity!(w, e2)
            new_entities!(w, 1, (A(0.0), B(0.0)))
            new_entities!(w, 1, (A(0.0), B(0.0), C() => e1))
            remove_entity!(w, e1)
            shuffle_entities!(w, Filter(w, (A, B)))
            sort_entities!(w, Filter(w, (A, B)))
            remove_entities!(w, Filter(w, (A, B)))
            remove_entities!(w, Filter(w, (A, B, C)))
            add_resource!(w, 1)
            set_resource!(w, get_resource(w, Int) + 1)
            remove_resource!(w, Int)
            reset!(w)
        end
        # world without relations
        @compile_workload let
            w = World(A, B => Storage{StructArray}, C; boxed=boxed)
            f = Filter(w, (A,); register=true)
            e1 = new_entity!(w, (A(0.0),))
            e2 = new_entity!(w, (A(0.0), B(0.0)))
            e3 = new_entity!(w, (A(0.0), B(0.0), C()))
            has_components(w, e1, (A,)) && get_components(w, e1, (A,))
            set_components!(w, e2, (A(1.0), B(1.0)))
            add_components!(w, e1, (B(0.0),))
            remove_components!(w, e1, (B,))
            add_components!(w, e1, (B(0.0), C()))
            remove_components!(w, e1, (B, C))
            exchange_components!(w, e2; add=(C(),), remove=(B,))
            collect(Query(w, (A,)))
            collect(Query(w, (A, B)))
            collect(Query(w, (A, B, C)))
            collect(Query(w, (A,); with=(B,), without=(C,)))
            collect(Query(w, f))
            copy_entity!(w, e3)
            remove_entity!(w, e3)
            new_entities!(w, 1, (A(0.0),))
            new_entities!(w, 1, (A(0.0), B(0.0)))
            shuffle_entities!(w, Filter(w, (A,)))
            sort_entities!(w, Filter(w, (A, B)))
            remove_entities!(w, Filter(w, (A,)))
            unregister!(w, f)
            reset!(w)
        end
    end
    # archetype graph paths for the common transition shapes (up to 4 components added/removed)
    @compile_workload begin
        for n_add in 0:4
            precompile(_find_or_create_path, (_Graph{1}, _NoGraphNode{1}, _Mask{1}, NTuple{n_add,Int}, Tuple{}))
        end
        for n_add in 0:4, n_rem in 0:4
            1 <= n_add + n_rem <= 4 || continue
            precompile(_find_or_create_path, (_Graph{1}, UInt32, _Mask{1}, NTuple{n_add,Int}, NTuple{n_rem,Int}))
        end
    end
end
