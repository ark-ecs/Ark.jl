@testset "Event type creation" begin
    reg = EventRegistry()

    e1 = new_event_type!(reg, :Event1)
    e2 = new_event_type!(reg, :Event2)
    @test e1._id == 7
    @test e2._id == 8

    @test string(reg) == "8-events EventRegistry()
 [:OnCreateEntity, :OnRemoveEntity, :OnAddComponents, :OnRemoveComponents, :OnAddRelations, :OnRemoveRelations, :Event1, :Event2]
"

    @test_throws "there is already an event with symbol :Event1" new_event_type!(reg, :Event1)

    cnt = 0
    for _ in 1:10
        new_event_type!(reg, Symbol(string(cnt)))
        cnt += 1
    end

    @test OnCreateEntity._id == 1
    @test OnRemoveEntity._id == 2
    @test OnAddComponents._id == 3
    @test OnRemoveComponents._id == 4
    @test OnAddRelations._id == 5
    @test OnRemoveRelations._id == 6

    @test string(OnCreateEntity) == "Event(:OnCreateEntity)"
end

@testset "Observer creation" begin
    world = World(Position, Velocity, Altitude, Health)

    obs = observe!(world, OnAddComponents, (Position, Velocity)) do entity
        println(entity)
    end

    M = (@isdefined fake_types) ? 5 : 1
    @test obs._comps == _Mask{M}(offset_ID + 1, offset_ID + 2)
    @test obs._with == _Mask{M}()
    @test obs._without == _Mask{M}()
    @test obs._has_comps == true
    @test obs._has_with == false
    @test obs._has_without == false

    obs = observe!(world, OnAddComponents, (Position, Velocity);
        with=(Altitude,),
        without=(Health,),
    ) do entity
        println(entity)
    end

    @test obs._comps == _Mask{M}(offset_ID + 1, offset_ID + 2)
    @test obs._with == _Mask{M}(offset_ID + 3)
    @test obs._without == _Mask{M}(offset_ID + 4)
    @test obs._has_comps == true
    @test obs._has_with == true
    @test obs._has_without == true

    obs = observe!(world, OnAddComponents, ();
        with=(Position, Velocity),
        exclusive=true,
    ) do entity
        println(entity)
    end

    @test obs._comps == _Mask{M}()
    @test obs._with == _Mask{M}(offset_ID + 1, offset_ID + 2)
    @test obs._without == _Mask{M}(_Not(), offset_ID + 1, offset_ID + 2)
    @test obs._has_comps == false
    @test obs._has_with == true
    @test obs._has_without == true

    @test_throws(
        "ArgumentError: components tuple must be empty for event types OnCreateEntity and OnRemoveEntity",
        observe!(world, OnCreateEntity, (Position, Velocity)) do entity
            println(entity)
        end,
    )

    @test_throws(
        "ArgumentError: all components must be relationships for event types OnAddRelations and OnRemoveRelations",
        observe!(world, OnAddRelations, (Position,)) do entity
            println(entity)
        end,
    )
end

@testset "Observer registration" begin
    world = World(Position, Velocity, Altitude, Health)
    @test _has_observers(world._event_manager, OnAddComponents) == false
    @test _has_observers(world._event_manager, OnRemoveComponents) == false

    observe!(world, OnAddComponents, ()) do entity
        println(entity)
    end
    obs1 = observe!(world, OnAddComponents, ()) do entity
        println(entity)
    end

    @test obs1._id.id == 2
    @test obs1._event._id == 3
    @test length(world._event_manager.observers) == _EVENT_MANAGER_INITIAL_CAPACITY
    @test length(world._event_manager.observers[OnAddComponents._id]) == 2
    @test length(world._event_manager.observers[OnRemoveComponents._id]) == 0
    @test _has_observers(world._event_manager, OnAddComponents) == true
    @test _has_observers(world._event_manager, OnRemoveComponents) == false

    obs2 = observe!(world, OnAddComponents, (Position,)) do entity
        println(entity)
    end

    @test obs2._id.id == 3
    @test length(world._event_manager.observers[OnAddComponents._id]) == 3

    @test_throws "InvalidStateException: observer is already registered" register!(obs1)

    unregister!(obs1)
    @test obs1._id.id == 0
    @test obs2._id.id == 2
    @test length(world._event_manager.observers[OnAddComponents._id]) == 2

    obs2 = observe!(world, OnAddComponents, (); with=(Position,)) do entity
        println(entity)
    end
    unregister!(obs2)

    @test_throws "InvalidStateException: observer is not registered" unregister!(obs1)

    obs3 = observe!(world, OnAddComponents, (); register=false) do entity
        println(entity)
    end
    @test obs3._id.id == 0
    @test length(world._event_manager.observers[OnAddComponents._id]) == 2

    @test length(world._event_manager.observers[OnRemoveComponents._id]) == 0
    @test _has_observers(world._event_manager, OnRemoveComponents) == false
    obs4 = observe!(world, OnRemoveComponents, ()) do entity
        println(entity)
    end
    @test length(world._event_manager.observers[OnRemoveComponents._id]) == 1
    @test _has_observers(world._event_manager, OnRemoveComponents) == true

    obs5 = observe!(world, OnRemoveComponents, (Position,)) do entity
        println(entity)
    end
    obs6 = observe!(world, OnRemoveComponents, (); with=(Position,)) do entity
        println(entity)
    end
    @test length(world._event_manager.observers[OnRemoveComponents._id]) == 3
    unregister!(obs4)
    unregister!(obs6)
    unregister!(obs5)
    @test _has_observers(world._event_manager, OnRemoveComponents) == false
end

@testset "Observer exclusive error" begin
    world = World()
    @test_throws("ArgumentError: cannot use 'exclusive' together with 'without'",
        observe!(world, OnCreateEntity, (); without=(Altitude,), exclusive=true) do entity
        end
    )
end

@testset "Fire OnCreateEntity" begin
    world = World(Dummy, Position, Velocity, Altitude)

    counter = 0
    obs = observe!(world, OnCreateEntity) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == false
        counter += 1
    end
    counter_remove = 0
    observe!(world, OnRemoveEntity) do entity
        counter_remove += 1
    end
    counter_rel = 0
    observe!(world, OnAddRelations) do entity
        counter_rel += 1
    end

    new_entity!(world, (Position(0, 0),))
    @test counter == 1

    unregister!(obs)

    observe!(world, OnCreateEntity, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnCreateEntity, (); with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    @test counter == 2
    new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    @test counter == 3
    new_entity!(world, (Position(0, 0),))
    @test counter == 3
    new_entity!(world, (Altitude(0),))
    @test counter == 3

    unregister!(obs)

    obs = observe!(world, OnCreateEntity; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    @test counter == 4
    new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    @test counter == 4

    @test counter_remove == 0
    @test counter_rel == 0
end

@testset "Fire OnAddRelations entity creation early out" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entity!(world, (ChildOf(),); relations=(ChildOf => parent,))
    @test counter == 0
end

@testset "Fire OnAddRelations entity creation filtered" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    obs = observe!(world, OnAddRelations, (ChildOf,)) do entity
        counter += 1
    end
    obs = observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entity!(world, (ChildOf(),); relations=(ChildOf => parent,))
    @test counter == 1
end

@testset "Fire OnAddRelations entity creation" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    counter = 0
    obs = observe!(world, OnAddRelations) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == false
        counter += 1
    end
    counter_remove = 0
    observe!(world, OnRemoveRelations) do entity
        counter_remove += 1
    end

    parent = new_entity!(world, ())

    new_entity!(world, (ChildOf(),); relations=(ChildOf => parent,))
    @test counter == 1

    unregister!(obs)

    observe!(world, OnAddRelations, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnAddRelations, (); with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 2
    new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 3
    new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 3
    new_entity!(world, (Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 3

    unregister!(obs)

    obs = observe!(world, OnAddRelations; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 4
    new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 4

    @test counter_remove == 0
end

@testset "Fire OnCreateEntity batch" begin
    world = World(Dummy, Position, Velocity, Altitude)

    counter = 0
    obs = observe!(world, OnCreateEntity) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end
    counter_rel = 0
    observe!(world, OnAddRelations) do entity
        counter_rel += 1
    end

    new_entities!(world, 10, (Position, Velocity)) do _
    end
    @test counter == 10

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    @test counter == 20

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0))) do _
        @test is_locked(world)
    end
    @test counter == 30

    unregister!(obs)

    observe!(world, OnCreateEntity, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnCreateEntity; with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    @test counter == 40
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    @test counter == 50
    new_entities!(world, 10, (Position(0, 0),))
    @test counter == 50
    new_entities!(world, 10, (Altitude(0),))
    @test counter == 50

    unregister!(obs)

    obs = observe!(world, OnCreateEntity; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    @test counter == 60
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    @test counter == 60

    @test counter_rel == 0
end

@testset "Fire OnRemoveEntity batch" begin
    world = World(Dummy, Position, Velocity, Altitude)

    counter = 0
    obs = observe!(world, OnRemoveEntity) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end
    counter_rel = 0
    observe!(world, OnRemoveRelations) do entity
        counter_rel += 1
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    remove_entities!(world, Filter(world, ()))
    @test counter == 10

    unregister!(obs)

    observe!(world, OnRemoveEntity, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnRemoveEntity; with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    remove_entities!(world, Filter(world, ()))
    @test counter == 20
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    remove_entities!(world, Filter(world, ()))
    @test counter == 30
    new_entities!(world, 10, (Position(0, 0),))
    remove_entities!(world, Filter(world, ()))
    @test counter == 30
    new_entities!(world, 10, (Altitude(0),))
    remove_entities!(world, Filter(world, ()))
    @test counter == 30

    unregister!(obs)

    obs = observe!(world, OnRemoveEntity; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0)))
    remove_entities!(world, Filter(world, ()))
    @test counter == 40
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    remove_entities!(world, Filter(world, ()))
    @test counter == 40

    @test counter_rel == 0
end

@testset "Fire OnAddRelations batch" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    counter = 0
    obs = observe!(world, OnAddRelations) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (Position, Velocity, ChildOf); relations=(ChildOf => parent,)) do _
    end
    @test counter == 10

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 20

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,)) do _
        @test is_locked(world) == true
    end
    @test counter == 30

    unregister!(obs)

    observe!(world, OnAddRelations, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnAddRelations; with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 40
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 50
    new_entities!(world, 10, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 50
    new_entities!(world, 10, (Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 50

    unregister!(obs)

    obs = observe!(world, OnAddRelations; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 60
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    @test counter == 60
end

@testset "Fire OnAddRelations batch early out" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (ChildOf(),); relations=(ChildOf => parent,))
    @test counter == 0
end

@testset "Fire OnAddRelations batch filtered" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    obs = observe!(world, OnAddRelations, (ChildOf,)) do entity
        counter += 1
    end
    obs = observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (ChildOf(),); relations=(ChildOf => parent,))
    @test counter == 10
end

@testset "Fire OnRemoveRelations batch" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    parent = new_entity!(world, ())
    filter = Filter(world, (ChildOf,); relations=(ChildOf => parent,), register=true)

    # create empty table
    remove_entity!(world,
        new_entity!(world,
            (Position(0, 0), Velocity(0, 0), Altitude(100), ChildOf());
            relations=(ChildOf => parent,),
        ),
    )

    counter = 0
    obs = observe!(world, OnRemoveRelations) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end
    observe!(world, OnRemoveEntity) do entity
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 10

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 20

    unregister!(obs)

    observe!(world, OnRemoveRelations, (); with=(Position,)) do entity
    end
    obs = observe!(world, OnRemoveRelations; with=(Position, Velocity)) do entity
        counter += 1
    end

    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 30
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 40
    new_entities!(world, 10, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 40
    new_entities!(world, 10, (Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 40

    unregister!(obs)

    obs = observe!(world, OnRemoveRelations; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 50
    new_entities!(world, 10, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,))
    remove_entities!(world, filter)
    @test counter == 50
end

@testset "Fire OnRemoveRelations batch early out" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counter += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (ChildOf(),); relations=(ChildOf => parent,))
    remove_entities!(world, Filter(world, (ChildOf,); relations=(ChildOf => parent,)))
    @test counter == 0
end

@testset "Fire OnAddRelations batch filtered" begin
    world = World(Dummy, ChildOf, ChildOf2)

    counter = 0
    obs = observe!(world, OnRemoveRelations, (ChildOf,)) do entity
        counter += 1
    end
    obs = observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counter += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (ChildOf(),); relations=(ChildOf => parent,))
    remove_entities!(world, Filter(world, (ChildOf,); relations=(ChildOf => parent,)))
    @test counter == 10
end

@testset "Fire OnRemoveEntity" begin
    world = World(Dummy, Position, Velocity, Altitude)

    counter = 0
    obs = observe!(world, OnRemoveEntity) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end
    counter_rel = 0
    observe!(world, OnRemoveRelations) do entity
        counter_rel += 1
    end

    remove_entity!(world, new_entity!(world, (Position(0, 0),)))
    @test counter == 1

    unregister!(obs)

    obs = observe!(world, OnRemoveEntity; with=(Position, Velocity)) do entity
        counter += 1
    end

    remove_entity!(world, new_entity!(world, (Position(0, 0), Velocity(0, 0))))
    @test counter == 2
    remove_entity!(world, new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0))))
    @test counter == 3
    remove_entity!(world, new_entity!(world, (Position(0, 0),)))
    @test counter == 3
    remove_entity!(world, new_entity!(world, (Altitude(0),)))
    @test counter == 3

    unregister!(obs)

    obs = observe!(world, OnRemoveEntity; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    remove_entity!(world, new_entity!(world, (Position(0, 0), Velocity(0, 0))))
    @test counter == 4
    remove_entity!(world, new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0))))
    @test counter == 4

    @test counter_rel == 0
end

@testset "Fire OnRemoveRelations entity removal" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    counter = 0
    obs = observe!(world, OnRemoveRelations) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter += 1
    end

    parent = new_entity!(world, ())

    remove_entity!(world, new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,)))
    @test counter == 1

    unregister!(obs)

    obs = observe!(world, OnRemoveRelations; with=(Position, Velocity)) do entity
        counter += 1
    end

    remove_entity!(
        world,
        new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,)),
    )
    @test counter == 2
    remove_entity!(
        world,
        new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,)),
    )
    @test counter == 3
    remove_entity!(world, new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,)))
    @test counter == 3
    remove_entity!(world, new_entity!(world, (Altitude(0), ChildOf()); relations=(ChildOf => parent,)))
    @test counter == 3

    unregister!(obs)

    obs = observe!(world, OnRemoveRelations; with=(Position, Velocity), without=(Altitude,)) do entity
        counter += 1
    end
    remove_entity!(
        world,
        new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent,)),
    )
    @test counter == 4
    remove_entity!(
        world,
        new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0), ChildOf()); relations=(ChildOf => parent,)),
    )
    @test counter == 4
end

@testset "Fire OnAddComponents/OnRemoveComponents" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddComponents) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == false
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveComponents) do entity
        @test is_alive(world, entity) == true
        @test is_locked(world) == true
        counter_rem += 1
    end
    counter_add_rel = 0
    counter_rem_rel = 0
    obs_add_rel = observe!(world, OnAddRelations) do entity
        counter_add_rel += 1
    end
    obs_rem_rel = observe!(world, OnRemoveRelations) do entity
        counter_rem_rel += 1
    end

    e = new_entity!(world, ())
    add_components!(world, e, (Position(0, 0),))
    @test counter_add == 1
    @test counter_rem == 0
    remove_components!(world, e, (Position,))
    @test counter_add == 1
    @test counter_rem == 1

    unregister!(obs_add)
    unregister!(obs_rem)

    obs_add = observe!(world, OnAddComponents, (Position, Velocity)) do entity
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveComponents, (Position, Velocity)) do entity
        counter_rem += 1
    end
    obs_add_dummy = observe!(world, OnAddComponents, (Position,)) do entity
    end
    obs_rem_dummy = observe!(world, OnRemoveComponents, (Position,)) do entity
    end

    e = new_entity!(world, ())
    add_components!(world, e, (Position(0, 0), Velocity(0, 0)))
    remove_components!(world, e, (Position, Velocity))
    @test counter_add == 2
    @test counter_rem == 2

    add_components!(world, e, (Altitude(0),))
    remove_components!(world, e, (Altitude,))
    @test counter_add == 2
    @test counter_rem == 2

    add_components!(world, e, (Position(0, 0),))
    remove_components!(world, e, (Position,))
    @test counter_add == 2
    @test counter_rem == 2

    @test counter_add_rel == 0
    @test counter_rem_rel == 0
end

@testset "Fire OnAddComponents/OnRemoveComponents with" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddComponents, (); with=(Position, Velocity)) do entity
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveComponents, (); with=(Position, Velocity)) do entity
        counter_rem += 1
    end
    obs_add_dummy = observe!(world, OnAddComponents, (); with=(Position,)) do entity
    end
    obs_rem_dummy = observe!(world, OnRemoveComponents, (); with=(Position,)) do entity
    end

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1

    e = new_entity!(world, (Altitude(0),))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0),))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1
end

@testset "Fire OnAddComponents/OnRemoveComponents without" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddComponents, (); without=(Position, Velocity)) do entity
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveComponents, (); without=(Position, Velocity)) do entity
        counter_rem += 1
    end
    obs_add_dummy = observe!(world, OnAddComponents, (); without=(Position,)) do entity
    end
    obs_rem_dummy = observe!(world, OnRemoveComponents, (); without=(Position,)) do entity
    end

    e = new_entity!(world, (Altitude(0),))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0),))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    add_components!(world, e, (Health(0),))
    remove_components!(world, e, (Health,))
    @test counter_add == 1
    @test counter_rem == 1
end

@testset "Fire OnAddRelations/OnRemoveRelations" begin
    world = World(Dummy, Position, Velocity, ChildOf, ChildOf2, ChildOf3)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == false
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == true
        counter_rem += 1
    end
    obs_add_2 = observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter_add += 1
    end
    obs_rem_2 = observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counter_rem += 1
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    entity = new_entity!(world, ())

    add_components!(world, entity, (ChildOf(),); relations=(ChildOf => parent1,))
    @test counter_add == 1
    @test counter_rem == 0

    add_components!(world, entity, (ChildOf2(),); relations=(ChildOf2 => parent1,))
    @test counter_add == 2
    @test counter_rem == 0

    set_relations!(world, entity, (ChildOf => parent2,))
    @test counter_add == 3
    @test counter_rem == 1

    set_relations!(world, entity, (ChildOf => parent2,))
    @test counter_add == 3
    @test counter_rem == 1

    set_relations!(world, entity, (ChildOf => parent1, ChildOf2 => parent2))
    @test counter_add == 5
    @test counter_rem == 3

    remove_components!(world, entity, (ChildOf,))
    @test counter_add == 5
    @test counter_rem == 4

    add_components!(world, entity, (ChildOf3(),); relations=(ChildOf3 => parent1,))
    @test counter_add == 5
    @test counter_rem == 4

    set_relations!(world, entity, (ChildOf3 => parent2,))
    @test counter_add == 5
    @test counter_rem == 4
end

@testset "Fire OnAddRelations/OnRemoveRelations with" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddRelations, (); with=(Position, Velocity)) do entity
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveRelations, (); with=(Position, Velocity)) do entity
        counter_rem += 1
    end
    obs_add_dummy = observe!(world, OnAddRelations, (); with=(Position,)) do entity
    end
    obs_rem_dummy = observe!(world, OnRemoveRelations, (); with=(Position,)) do entity
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    @test counter_add == 1
    @test counter_rem == 0

    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1

    e = new_entity!(world, (Altitude(0), ChildOf()); relations=(ChildOf => parent1,))
    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1
end

@testset "Fire OnAddRelations/OnRemoveRelations without" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddRelations, (); without=(Position, Velocity)) do entity
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveRelations, (); without=(Position, Velocity)) do entity
        counter_rem += 1
    end
    obs_add_dummy = observe!(world, OnAddRelations, (); without=(Position,)) do entity
    end
    obs_rem_dummy = observe!(world, OnRemoveRelations, (); without=(Position,)) do entity
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    e = new_entity!(world, (Altitude(0), ChildOf()); relations=(ChildOf => parent1,))
    @test counter_add == 1
    @test counter_rem == 0

    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    set_relations!(world, e, (ChildOf => parent2,))
    @test counter_add == 2
    @test counter_rem == 1
end

@testset "Fire OnAddRelations/OnRemoveRelations batch" begin
    world = World(Dummy, Position, Velocity, ChildOf, ChildOf2, ChildOf3)

    counter_add = 0
    counter_rem = 0
    obs_add = observe!(world, OnAddRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == true
        counter_add += 1
    end
    obs_rem = observe!(world, OnRemoveRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == true
        counter_rem += 1
    end
    obs_add_2 = observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counter_add += 1
    end
    obs_rem_2 = observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counter_rem += 1
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())

    new_entities!(world, 10, (Position(1, 1), ChildOf()); relations=(ChildOf => parent1,))
    new_entities!(world, 10, (Position(1, 1), ChildOf()); relations=(ChildOf => parent2,))
    new_entities!(world, 10, (Position(1, 1), ChildOf()); relations=(ChildOf => parent3,))

    @test counter_add == 30
    @test counter_rem == 0

    set_relations!(world, Filter(world, (ChildOf,); relations=(ChildOf => parent2,)), (ChildOf => parent1,))

    @test counter_add == 40
    @test counter_rem == 10

    set_relations!(world, Filter(world, (ChildOf,); relations=(ChildOf => parent2,)), (ChildOf => parent1,))

    @test counter_add == 40
    @test counter_rem == 10

    set_relations!(world, Filter(world, (ChildOf,)), (ChildOf => parent2,))

    @test counter_add == 70
    @test counter_rem == 40

    remove_entities!(world, Filter(world, ()))

    @test counter_add == 70
    @test counter_rem == 70
end

@testset "Fire batch exchange events" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counters = Int[0, 0, 0, 0]
    observe!(world, OnAddComponents, (Velocity,)) do entity
        @test _is_locked(world._lock) == true
        counters[1] += 1
    end
    observe!(world, OnRemoveComponents, (Velocity,)) do entity
        @test _is_locked(world._lock) == true
        counters[2] += 1
    end
    observe!(world, OnAddComponents, (Altitude,)) do entity
        counters[1] += 1
    end
    observe!(world, OnRemoveComponents, (Altitude,)) do entity
        counters[2] += 1
    end

    observe!(world, OnAddRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == true
        counters[3] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,)) do entity
        @test _is_locked(world._lock) == true
        counters[4] += 1
    end
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counters[3] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counters[4] += 1
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0),))
    @test counters == [0, 0, 0, 0]

    add_components!(world, Filter(world, (Position,)), (Velocity(1, 1),))
    @test counters == [10, 0, 0, 0]

    remove_components!(world, Filter(world, (Velocity,)), (Velocity,))
    @test counters == [10, 10, 0, 0]

    add_components!(world, Filter(world, (Position,)), (ChildOf(),); relations=(ChildOf => parent1,))
    @test counters == [10, 10, 10, 0]

    remove_components!(world, Filter(world, (ChildOf,)), (ChildOf,))
    @test counters == [10, 10, 10, 10]
end

@testset "Fire batch exchange early out" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counters = Int[0, 0]
    observe!(world, OnAddRelations, (ChildOf2,)) do entity
        counters[1] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf2,)) do entity
        counters[2] += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0),))
    @test counters == [0, 0]

    add_components!(world, Filter(world, (Position,)), (ChildOf(),); relations=(ChildOf => parent,))
    @test counters == [0, 0]

    remove_components!(world, Filter(world, (ChildOf,)), (ChildOf,))
    @test counters == [0, 0]
end

@testset "Fire batch exchange with" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counters = Int[0, 0]
    observe!(world, OnAddRelations, (ChildOf,); with=(Position,)) do entity
        counters[1] += 1
    end
    observe!(world, OnAddRelations, (ChildOf,); with=(Velocity,)) do entity
        counters[1] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); with=(Position,)) do entity
        counters[2] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); with=(Velocity,)) do entity
        counters[2] += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0),))
    @test counters == [0, 0]

    add_components!(world, Filter(world, (Position,)), (ChildOf(),); relations=(ChildOf => parent,))
    @test counters == [10, 0]

    remove_components!(world, Filter(world, (ChildOf,)), (ChildOf,))
    @test counters == [10, 10]
end

@testset "Fire batch exchange with early out" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counters = Int[0, 0]
    observe!(world, OnAddRelations, (ChildOf,); with=(Velocity,)) do entity
        counters[1] += 1
    end
    observe!(world, OnAddRelations, (ChildOf,); with=(Altitude,)) do entity
        counters[1] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); with=(Velocity,)) do entity
        counters[2] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); with=(Altitude,)) do entity
        counters[2] += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0),))
    @test counters == [0, 0]

    add_components!(world, Filter(world, (Position,)), (ChildOf(),); relations=(ChildOf => parent,))
    @test counters == [0, 0]

    remove_components!(world, Filter(world, (ChildOf,)), (ChildOf,))
    @test counters == [0, 0]
end

@testset "Fire batch exchange without" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf, ChildOf2)

    counters = Int[0, 0]
    observe!(world, OnAddRelations, (ChildOf,); without=(Position,)) do entity
        counters[1] += 1
    end
    observe!(world, OnAddRelations, (ChildOf,); without=(Velocity,)) do entity
        counters[1] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); without=(Position,)) do entity
        counters[2] += 1
    end
    observe!(world, OnRemoveRelations, (ChildOf,); without=(Velocity,)) do entity
        counters[2] += 1
    end

    parent = new_entity!(world, ())

    new_entities!(world, 10, (Position(0, 0),))
    @test counters == [0, 0]

    add_components!(world, Filter(world, (Position,)), (ChildOf(),); relations=(ChildOf => parent,))
    @test counters == [10, 0]

    remove_components!(world, Filter(world, (ChildOf,)), (ChildOf,))
    @test counters == [10, 10]
end

@testset "Observers combine" begin
    world = World(Dummy, Position, Velocity)

    counter = 0
    fn = (event::Event, entity::Entity) -> begin
        counter += 1
    end
    obs_add = observe!(world, OnCreateEntity) do entity
        fn(OnCreateEntity, entity)
    end
    obs_rem = observe!(world, OnRemoveEntity) do entity
        fn(OnRemoveEntity, entity)
    end

    e = new_entity!(world, ())
    @test counter == 1
    remove_entity!(world, e)
    @test counter == 2
end

@testset "Fire custom event" begin
    reg = EventRegistry()
    OnUpdateComponents = new_event_type!(reg, :OnUpdateComponents)
    world = World(Dummy, Position, Velocity, Altitude, Health)

    e = new_entity!(world, ())
    emit_event!(world, OnUpdateComponents, e)

    counter = 0
    obs = observe!(world, OnUpdateComponents) do entity
        if counter == 0
            @test is_zero(entity) == true
        else
            @test is_alive(world, entity) == true
        end
        @test is_locked(world) == false
        counter += 1
    end

    emit_event!(world, OnUpdateComponents, zero_entity)
    @test counter == 1

    e = new_entity!(world, (Position(0, 0),))
    emit_event!(world, OnUpdateComponents, e, (Position,))
    @test counter == 2

    unregister!(obs)

    obs = observe!(world, OnUpdateComponents, (Position, Velocity)) do entity
        counter += 1
    end
    obs_dummy = observe!(world, OnUpdateComponents, (Position,)) do entity
    end

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0), Altitude(0)))
    emit_event!(world, OnUpdateComponents, e, (Position, Velocity))
    @test counter == 3

    emit_event!(world, OnUpdateComponents, e, (Altitude,))
    @test counter == 3

    emit_event!(world, OnUpdateComponents, e, (Position,))
    @test counter == 3
end

@testset "Fire custom event with" begin
    reg = EventRegistry()
    OnUpdateComponents = new_event_type!(reg, :OnUpdateComponents)
    world = World(Dummy, Position, Velocity, Altitude, Health)

    counter = 0
    obs = observe!(world, OnUpdateComponents, (); with=(Position, Velocity)) do entity
        counter += 1
    end
    obs_dummy = observe!(world, OnUpdateComponents, (); with=(Position,)) do entity
    end

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1

    e = new_entity!(world, (Altitude(0),))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1

    e = new_entity!(world, (Position(0, 0),))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1
end

@testset "Fire custom event without" begin
    reg = EventRegistry()
    OnUpdateComponents = new_event_type!(reg, :OnUpdateComponents)
    world = World(Dummy, Position, Velocity, Altitude, Health)

    counter = 0
    obs = observe!(world, OnUpdateComponents, (); without=(Position, Velocity)) do entity
        counter += 1
    end
    obs_dummy = observe!(world, OnUpdateComponents, (); without=(Position,)) do entity
    end

    e = new_entity!(world, (Altitude(0),))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1

    e = new_entity!(world, (Position(0, 0),))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    emit_event!(world, OnUpdateComponents, e)
    @test counter == 1
end

@testset "Fire custom event errors" begin
    reg = EventRegistry()
    OnUpdateComponents = new_event_type!(reg, :OnUpdateComponents)
    world = World(Dummy, Position, Velocity, Altitude, Health)
    observe!(world, OnUpdateComponents, ()) do entity
    end

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))

    @test_throws("ArgumentError: only custom events can be emitted manually",
        emit_event!(world, OnCreateEntity, e, ()))
    @test_throws("ArgumentError: can't emit event with components for the zero entity",
        emit_event!(world, OnUpdateComponents, zero_entity, (Position,)))

    remove_entity!(world, e)
    @test_throws("ArgumentError: can't emit event for a dead entity",
        emit_event!(world, OnUpdateComponents, e, ()))

    e = new_entity!(world, (Position(0, 0), Velocity(0, 0)))
    @test_throws("ArgumentError: entity does not have all components of the event emitted for it",
        emit_event!(world, OnUpdateComponents, e, (Position, Altitude)))
end

@testset "custom event without registered observers does not throw" begin
    world = World()

    # Make num_observers > 0 without extending storage to custom event ids
    observe!(_ -> nothing, world, OnCreateEntity)

    registry = EventRegistry()
    evt = new_event_type!(registry, :MyEvent)

    @test emit_event!(world, evt, zero_entity) === nothing
end

@testset "Observer show" begin
    world = World(
        Position,
        Velocity,
        Altitude,
        Health,
        CompN{1},
    )
    obs = observe!(world, OnAddComponents, (Position, Velocity)) do _
    end
    @test string(obs) == "Observer(:OnAddComponents, (Position, Velocity))"

    obs = observe!(world, OnAddComponents, (Position, Velocity); with=(Health,), exclusive=true) do _
    end
    @test string(obs) == "Observer(:OnAddComponents, (Position, Velocity); with=(Health), exclusive=true)"

    obs = observe!(world, OnAddComponents, (Position, Velocity); without=(Health,)) do _
    end
    @test string(obs) == "Observer(:OnAddComponents, (Position, Velocity); without=(Health))"
end
