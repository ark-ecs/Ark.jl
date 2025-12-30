
using PrecompileTools

@setup_workload let
    struct A
        x::Float64
    end
    struct B
        x::Float64
    end
    struct C <: Relationship end
    @compile_workload let
        w = World(A, B => StructArrayStorage, C)
        e1 = new_entity!(w, (A(0.0), B(0.0)))
        e2 = new_entity!(w, (A(0.0), B(0.0), C()); relations=(C => e1,))
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
        add_components!(w, e2, (A(0.0), C()); relations=(C => e1,))
        e1, = get_relations(w, e2, (C,))
        add_components!(w, e3, (C(),); relations=(C => e2,))
        set_relations!(w, e3, (C => e1,))
        remove_entity!(w, e2)
        new_entities!(w, 1, (A(0.0), B(0.0)))
        new_entities!(w, 1, (A(0.0), B(0.0), C()); relations=(C => e1,))
        remove_entity!(w, e1)
        remove_entities!(w, Filter(w, (A, B)))
        remove_entities!(w, Filter(w, (A, B, C)))
        add_resource!(w, 1)
        set_resource!(w, get_resource(w, Int) + 1)
        remove_resource!(w, Int)
        reset!(w)
    end
end
