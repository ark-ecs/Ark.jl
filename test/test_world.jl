
@testset "World creation" begin
    world = World()
    @test isa(world, World)
    @test isa(world._registry, _ComponentRegistry)

    !(@isdefined fake_types) && @test world._storages == ()
    @test length(world._archetypes) == 1
end

@testset "World creation 2" begin
    world = World(
        Position,
        Velocity => Storage{StructArray},
        Altitude,
        ChildOf,
    )
    @test isa(world, World)
    params = typeof(world).parameters[1]

    @test _component_id(params, Velocity) == offset_ID + 2
    @test _component_id(params, Position) == offset_ID + 1
    @test_throws(
        "ArgumentError: Component type Health not found in the World",
        _component_id(params, Health))

    @test isa(_get_storage(world, Position), _ComponentStorage{Position,_storage_from_component(world, Position)})
    @test isa(_get_storage(world, Position).data[1], _storage_from_component(world, Position))
    @test isa(_get_storage(world, Velocity), _ComponentStorage{Velocity,_StructArray_type(Velocity)})
    @test isa(_get_storage(world, Velocity).data[1], _StructArray_type(Velocity))
    @test isa(_get_storage(world, Altitude), _ComponentStorage{Altitude,_storage_from_component(world, Altitude)})
    @test isa(_get_storage(world, Altitude).data[1], _storage_from_component(world, Altitude))

    @test length(_get_relations_storage(world, Position).archetypes) == 0
    @test length(_get_relations_storage(world, Position).targets) == 0
    @test length(_get_relations_storage(world, ChildOf).archetypes) == 1
    @test length(_get_relations_storage(world, ChildOf).targets) == 1
    @test _get_relations_storage(world, ChildOf).archetypes[1] == 0
    @test _get_relations_storage(world, ChildOf).targets[1] == _no_entity
end

@testset "World show" begin
    world = World(
        Position,
        Velocity,
        CompN{1},
        CompN{Int64},
        Float64,
    )
    new_entities!(world, 100, ())

    if offset_ID == 0
        @test string(world) == "World(entities=100, comp_types=(Position, Velocity, CompN{1}, CompN{Int64}, Float64))"
    else
        @test startswith(string(world), "World(entities=100, comp_types=(FakeComp{1}, FakeComp{2}, ")
    end
end

@testset "World storage type" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
    )

    @test isa(_get_storage(world, Position), _ComponentStorage{Position,_storage_from_component(world, Position)})
    @test isa(_get_storage(world, Velocity), _ComponentStorage{Velocity,_StructArray_type(Velocity)})
end

"""
@static if RUN_JET
    @testset "World creation JET" begin
        # TODO: type instability here. Add benchmarks for world creation.
        @test_opt World(
            Position,
            Velocity => Storage{StructArray},
        )
    end
end
"""

@testset "World creation error" begin
    @test_throws(
        "ArgumentError: duplicate component type Velocity during world creation",
        World(Position, Velocity, Velocity))

    @test_throws(
        "ArgumentError: can't use Relationship as component as it is not a concrete type",
        World(Position, Velocity, Relationship))

    @test_throws(
        "ArgumentError: Health is not a valid storage mode, must be Storage{T<:AbstractVector}",
        World(Position, Velocity, Altitude => Health))

    @test_throws(
        "ArgumentError: can't use Storage{StructArray} for Int64 because it has no fields",
        World(Int64 => Storage{StructArray}))

    @test_throws(
        "ArgumentError: can't use Storage{StructArray} for LabelComponent because it has no fields",
        World(LabelComponent => Storage{StructArray}))
end

@testset "World creation large" begin
    world = World(
        CompN{1}, CompN{2}, CompN{3}, CompN{4}, CompN{5},
        CompN{6}, CompN{7}, CompN{8}, CompN{9}, CompN{10},
        CompN{11}, CompN{12}, CompN{13}, CompN{14}, CompN{15},
        CompN{16}, CompN{17}, CompN{18}, CompN{19}, CompN{20},
        CompN{21}, CompN{22}, CompN{23}, CompN{24}, CompN{25},
        CompN{26}, CompN{27}, CompN{28}, CompN{29}, CompN{30},
        Position, Velocity,
    )

    @test length(world._storages) == N_fake + 32
end

@testset "World create table" begin
    world = World(Position, Velocity)

    table1 = _find_or_create_table!(
        world,
        world._tables[1],
        (offset_ID + 1,),
        (),
        (),
        (),
        _Mask{M_mask}(offset_ID + 1),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test table1 == (2, false)
    @test world._tables[table1[1]].archetype == 2
    @test length(world._tables) == 2

    table2 = _find_or_create_table!(
        world,
        world._tables[1],
        (offset_ID + 1, offset_ID + 2),
        (),
        (),
        (),
        _Mask{M_mask}(offset_ID + 1, offset_ID + 2),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test table2 == (3, false)
    @test world._tables[table2[1]].archetype == 3
    @test length(world._tables) == 3

    table3 = _find_or_create_table!(
        world,
        world._tables[1],
        (offset_ID + 1,),
        (),
        (),
        (),
        _Mask{M_mask}(offset_ID + 1),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test table3 == table1
    @test length(world._tables) == 3
end

@testset "World Component Registration" begin
    world = World(Int, Position)
    params = typeof(world).parameters[1]

    # Register Int component
    id_int = _component_id(params, Int)
    @test isa(id_int, Int)
    @test world._registry.types[id_int] == Int
    @test length(world._storages) == N_fake + 2
    @test world._storages[id_int] isa _ComponentStorage{Int,_storage_from_component(world, Int)}
    @test length(world._storages[id_int].data) == 1

    # Register Position component
    id_pos = _component_id(params, Position)
    @test isa(id_pos, Int)
    @test world._registry.types[id_pos] == Position
    @test length(world._storages) == N_fake + 2
    @test world._storages[id_pos] isa _ComponentStorage{Position,_storage_from_component(world, Position)}
    @test length(world._storages[id_pos].data) == 1

    # Re-register Int component (should not add new storage)
    id_int2 = _component_id(params, Int)
    @test id_int2 == id_int
    @test length(world._storages) == N_fake + 2

    @test_throws("ArgumentError: Component type Velocity not found in the World",
        _component_id(params, Velocity))

    @test_throws("ArgumentError: Component type MutableComponent must be immutable unless 'allow_mutable' is used",
        World(Position, MutableComponent))

    _ = World(Position, MutableComponent; allow_mutable=true)

    @test_throws("ArgumentError: Component type MutableComponent must be immutable because it uses StructArray storage",
        World(Position, MutableComponent => Storage{StructArray}))
end

@testset "_get_storage Tests" begin
    world = World(Int)
    params = typeof(world).parameters[1]

    storage1 = _get_storage(world, Int)
    @test storage1 isa _ComponentStorage{Int,_storage_from_component(world, Int)}

    id = _component_id(params, Int)
    storage2 = _get_storage(world, Int)
    @test storage2 isa _ComponentStorage{Int,_storage_from_component(world, Int)}

    @test storage1 === storage2

    @test_throws("ArgumentError: Component type Float64 not found in the World",
        _get_storage(world, Float64))

    @test_throws("ArgumentError: Component type Float64 not found in the World",
        _get_relations_storage(world, Float64))
end

@testset "_find_or_create_table! Tests" begin
    world = World(Position, Velocity)
    params = typeof(world).parameters[1]

    pos_id = _component_id(params, Position)
    @test pos_id == offset_ID + UInt8(1)

    index = _find_or_create_table!(
        world,
        world._tables[1],
        (pos_id,),
        (),
        (),
        (),
        _Mask{M_mask}(pos_id),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test index == (2, false)
    @test length(world._tables) == 2
    @test length(world._archetypes) == 2

    vel_id = _component_id(params, Velocity)
    @test vel_id == offset_ID + UInt8(2)

    index = _find_or_create_table!(
        world,
        world._tables[1],
        (pos_id, vel_id),
        (),
        (),
        (),
        _Mask{M_mask}(pos_id, vel_id),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test index == (3, false)
    @test length(world._tables) == 3
    @test length(world._archetypes) == 3

    index = _find_or_create_table!(
        world,
        world._tables[1],
        (pos_id, vel_id),
        (),
        (),
        (),
        _Mask{M_mask}(pos_id, vel_id),
        _Mask{M_mask}(),
        _UseMap(),
        Val(false),
    )
    @test index == (3, false)
    @test length(world._tables) == 3
    @test length(world._archetypes) == 3

    @test world._archetypes[2].components == [pos_id]
    @test world._archetypes[3].components == [pos_id, vel_id]

    @test length(world._storages) == N_fake + 2
    @test length(world._registry.types) == N_fake + 2

    pos_storage = _get_storage(world, Position)
    vel_storage = _get_storage(world, Velocity)

    @test isa(pos_storage, _ComponentStorage{Position,_storage_from_component(world, Position)})
    @test isa(vel_storage, _ComponentStorage{Velocity,_storage_from_component(world, Velocity)})
    @test length(pos_storage.data) == 3
    @test length(vel_storage.data) == 3
end

@testset "_create_entity! Tests" begin
    world = World(Position, Velocity)
    params = typeof(world).parameters[1]
    pos_id = _component_id(params, Position)
    vel_id = _component_id(params, Velocity)
    table_index = _find_or_create_table!(
        world,
        world._tables[1],
        (pos_id, vel_id),
        (),
        (),
        (),
        _Mask{M_mask}(pos_id, vel_id),
        _Mask{M_mask}(),
        _NoUseMap(),
        Val(false),
    )
    @test table_index == (2, false)

    entity, index = _create_entity!(world, table_index[1])
    push!(_get_storage(world, Position).data[table_index[1]], Position(0, 0))
    push!(_get_storage(world, Velocity).data[table_index[1]], Velocity(0, 0))
    @test entity == _new_entity(2, 0)
    @test index == 1
    @test world._entities == [_EntityIndex(typemax(UInt32), 0), _EntityIndex(table_index[1], UInt32(1))]

    remove_entity!(world, entity)
    entity, index = _create_entity!(world, table_index[1])
    push!(_get_storage(world, Position).data[table_index[1]], Position(0, 0))
    push!(_get_storage(world, Velocity).data[table_index[1]], Velocity(0, 0))
    @test entity == _new_entity(2, 1)

    pos_storage = _get_storage(world, Position)
    vel_storage = _get_storage(world, Velocity)

    @test length(pos_storage.data[table_index[1]]) == 1
    @test length(vel_storage.data[table_index[1]]) == 1
end

@testset "World get/set components" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
    )

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    e2 = new_entity!(world, ())

    pos, vel = get_components(world, e1, (Position, Velocity))
    @test pos == Position(1, 2)
    @test vel == Velocity(3, 4)

    # TODO: do we want that, or do we want it to return `nothing`?
    @test_throws("ArgumentError: entity has no Position component",
        get_components(world, e2, (Position, Velocity)))
    @test_throws("ArgumentError: entity has no Position component",
        set_components!(world, e2, (Position(0, 0),)))
    @test_throws("ArgumentError: can't get components of a dead entity",
        get_components(world, zero_entity, (Position, Velocity)))

    t = get_components(world, e1, ())
    @test t == ()

    set_components!(world, e1, (Position(5, 6), Velocity(7, 8)))
    pos, vel = get_components(world, e1, (Position, Velocity))
    @test pos == Position(5, 6)
    @test vel == Velocity(7, 8)
end

@static if RUN_JET
    @testset "World get/set components JET" begin
        world = World(
            Position,
            Velocity => Storage{StructArray},
        )
        e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))

        #@test_opt get_components(world, e1, (Position, Velocity))
        @test_opt set_components!(world, e1, (Position(5, 6), Velocity(7, 8)))
    end
end

@testset "World new_entity! Tests" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
    )

    entity = new_entity!(world, ())
    @test entity == _new_entity(2, 0)
    @test is_alive(world, entity) == true

    entity = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    @test entity == _new_entity(3, 0)
    @test is_alive(world, entity) == true
    @test length(world._storages[offset_ID+2].data[2]) == 1
    @test length(world._storages[offset_ID+3].data[2]) == 1

    pos, vel = get_components(world, entity, (Position, Velocity))
    @test pos == Position(1, 2)
    @test vel == Velocity(3, 4)

    @test_throws(
        "ArgumentError: duplicate component types: Position",
        new_entity!(world, (Position(1, 2), Position(3, 4)))
    )

    remove_entity!(world, entity)
    @test is_alive(world, entity) == false
end

@static if RUN_JET
    @testset "World new_entity! JET" begin
        world = World(
            Position,
            Velocity => Storage{StructArray},
        )

        using FunctionWrappers
        excluded = Set([
            FunctionWrappers.gen_fptr,
            Base.unsafe_convert,
            Base.setproperty!,
        ])
        function_filter(@nospecialize f) = !(f in excluded)

        @test_opt function_filter = function_filter new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    end
end

@testset "World new_entity! relations" begin
    world = World(
        Dummy,
        Position,
        ChildOf,
        Velocity => Storage{StructArray},
    )

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    dead_parent = new_entity!(world, ())
    remove_entity!(world, dead_parent)

    @test world._targets[parent1._id] == false

    e1 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    e2 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent2,))
    e3 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent2,))

    @test world._targets[parent1._id] == true

    @test length(world._archetypes) == 2
    @test length(world._tables) == 3

    arch = world._archetypes[2]
    @test length(arch.index[1]) == 2
    @test arch.index[1][parent1._id].ids == [2]
    @test arch.index[1][parent2._id].ids == [3]

    e4 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent2,))
    @test get_relations(world, e4, (ChildOf,)) == get_relations(world, e2, (ChildOf,))

    @test_throws(
        "ArgumentError: all relations must be in the set of component types",
        new_entity!(world, (Position(0, 0),); relations=(ChildOf => parent1,))
    )
    @test_throws(
        "ArgumentError: component Position is not a relationship",
        new_entity!(world, (Position(0, 0),); relations=(Position => parent1,))
    )
    @test_throws(
        "ArgumentError: duplicate component types: ChildOf",
        new_entity!(world, (ChildOf(),); relations=(ChildOf => parent1, ChildOf => parent2))
    )
    @test_throws(
        "ArgumentError: can't use a dead entity as relation target, except for the zero entity",
        new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => dead_parent,)),
    )
end

@testset "World new_entity! multiple relations" begin
    world = World(
        Dummy,
        Position,
        ChildOf,
        ChildOf2,
    )

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    e1 = new_entity!(world, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent1, ChildOf2 => parent2))
    e2 = new_entity!(world, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent2, ChildOf2 => parent1))
    e3 = new_entity!(world, (Position(0, 0), ChildOf(), ChildOf2());
        relations=(ChildOf => parent1, ChildOf2 => parent2))

    @test length(world._archetypes[2].tables) == 2
    @test get_relations(world, e1, (ChildOf, ChildOf2)) == (parent1, parent2)
    @test get_relations(world, e2, (ChildOf, ChildOf2)) == (parent2, parent1)
    @test get_relations(world, e3, (ChildOf, ChildOf2)) == (parent1, parent2)

    remove_entity!(world, parent1)
    remove_entity!(world, parent2)

    @test length(world._archetypes[2].tables) == 1

    @test get_relations(world, e1, (ChildOf, ChildOf2)) == (zero_entity, zero_entity)
    @test get_relations(world, e2, (ChildOf, ChildOf2)) == (zero_entity, zero_entity)
    @test get_relations(world, e3, (ChildOf, ChildOf2)) == (zero_entity, zero_entity)
end

@testset "World get/set relations" begin
    world = World(
        Dummy,
        Position,
        ChildOf,
        ChildOf2,
    )

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    dead_parent = new_entity!(world, ())
    remove_entity!(world, dead_parent)

    entity1 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    entity2 = new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    entity3 = new_entity!(world,
        (Position(0, 0), ChildOf2(), ChildOf());
        relations=(ChildOf => parent2, ChildOf2 => parent1),
    )

    @test get_relations(world, entity1, (ChildOf,)) == (parent1,)
    @test get_relations(world, entity3, (ChildOf,)) == (parent2,)

    @test get_relations(world, entity3, (ChildOf2,)) == (parent1,)

    @test get_relations(world, entity3, (ChildOf, ChildOf2)) == (parent2, parent1)

    set_relations!(world, entity1, (ChildOf => parent2,))
    @test get_relations(world, entity1, (ChildOf,)) == (parent2,)
    @test get_relations(world, entity2, (ChildOf,)) == (parent1,)

    @test get_relations(world, entity2, ()) == ()

    set_relations!(world, entity1, (ChildOf => parent2,))
    @test get_relations(world, entity1, (ChildOf,)) == (parent2,)

    @test_throws(
        "ArgumentError: duplicate component types: ChildOf",
        get_relations(world, entity1, (ChildOf, ChildOf)),
    )
    @test_throws(
        "ArgumentError: component Position is not a relationship",
        get_relations(world, entity1, (Position,)),
    )
    @test_throws(
        "ArgumentError: entity does not have relationship component ChildOf2",
        get_relations(world, entity1, (ChildOf2,)),
    )
    @test_throws(
        "ArgumentError: can't get relations of a dead entity",
        get_relations(world, zero_entity, (ChildOf,)),
    )

    @test_throws(
        "ArgumentError: duplicate component types: ChildOf",
        set_relations!(world, entity1, (ChildOf => parent1, ChildOf => parent1)),
    )
    @test_throws(
        "ArgumentError: component Position is not a relationship",
        set_relations!(world, entity1, (Position => parent1,)),
    )
    @test_throws(
        "ArgumentError: entity does not have the requested relationship component",
        set_relations!(world, entity1, (ChildOf2 => parent1,)),
    )
    @test_throws(
        "ArgumentError: can't set relation targets of a dead entity",
        set_relations!(world, zero_entity, (ChildOf => parent1,)),
    )
    @test_throws(
        "ArgumentError: can't use a dead entity as relation target, except for the zero entity",
        set_relations!(world, entity1, (ChildOf => dead_parent,)),
    )
end

@testset "World set relations batch" begin
    world = World(
        Dummy,
        Position,
        ChildOf,
        ChildOf2,
    )
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    parent3 = new_entity!(world, ())
    parent4 = new_entity!(world, ())
    dead_parent = new_entity!(world, ())
    remove_entity!(world, dead_parent)

    filter1 = Filter(world, (ChildOf,); relations=(ChildOf => parent1,), register=true)
    filter2 = Filter(world, (ChildOf,); register=true)

    e1 = new_entity!(world, (Position(1, 1), ChildOf()); relations=(ChildOf => parent1,))
    e2 = new_entity!(world, (Position(2, 2), ChildOf()); relations=(ChildOf => parent1,))
    e3 = new_entity!(world, (Position(3, 3), ChildOf()); relations=(ChildOf => parent2,))
    e4 = new_entity!(world, (Position(4, 4), ChildOf()); relations=(ChildOf => parent2,))
    e5 = new_entity!(world, (Position(5, 5), ChildOf()); relations=(ChildOf => parent3,))
    e6 = new_entity!(world, (Position(6, 6), ChildOf()); relations=(ChildOf => parent3,))

    count = 0
    set_relations!(world, filter1, (ChildOf => parent2,)) do entities
        @test length(entities) == 2
        count += 1
    end
    @test count == 1

    @test get_relations(world, e1, (ChildOf,)) == (parent2,)
    @test get_relations(world, e2, (ChildOf,)) == (parent2,)

    count = 0
    total = 0
    set_relations!(world, Filter(world, (ChildOf,)), (ChildOf => parent1,)) do entities
        count += 1
        total += length(entities)
    end
    @test count == 2
    @test total == 6
    for (i, e) in enumerate([e1, e2, e3, e4, e5, e6])
        @test get_relations(world, e, (ChildOf,)) == (parent1,)
        @test get_components(world, e, (Position,)) == (Position(i, i),)
    end

    count = 0
    set_relations!(world, Filter(world, (ChildOf,); relations=(ChildOf => parent2,)), (ChildOf => parent1,)) do entities
        count += 1
    end
    @test count == 0

    count = 0
    set_relations!(world, filter1, (ChildOf => parent1,)) do entities
        count += 1
    end
    @test count == 0

    set_relations!(world, filter2, (ChildOf => parent4,))
    for (i, e) in enumerate([e1, e2, e3, e4, e5, e6])
        @test get_relations(world, e, (ChildOf,)) == (parent4,)
        @test get_components(world, e, (Position,)) == (Position(i, i),)
    end
    @test world._targets[parent4._id] == true

    @test_throws(
        "ArgumentError: can't use a dead entity as relation target, except for the zero entity",
        set_relations!(world, filter2, (ChildOf => dead_parent,))
    )

    @test count_entities(Filter(world, (ChildOf,))) == 6
end

@testset "World copy_entity!" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        ChildOf,
    )

    counter = 0
    observe!(world, OnCreateEntity; with=(Position,)) do entity
        @test entity._id == counter + 3
        counter += 1
    end
    counter_rel = 0
    observe!(world, OnAddRelations; with=(Position,)) do entity
        @test entity._id == counter_rel + 3
        counter_rel += 1
    end

    parent = new_entity!(world, ())

    entity = new_entity!(world, (Position(1, 2), Velocity(3, 4), ChildOf()); relations=(ChildOf => parent,))
    entity2 = copy_entity!(world, entity)

    @test counter == 2
    @test counter_rel == 2

    @test entity2._id == entity._id + 1
    @test entity2._id == 4
    @test world._tables[2].entities == [entity, entity2]
    @test length(world._storages[offset_ID+2].data[2]) == 2
    @test length(world._storages[offset_ID+3].data[2]) == 2

    pos, vel = get_components(world, entity2, (Position, Velocity))
    @test pos == Position(1, 2)
    @test vel == Velocity(3, 4)

    @test get_relations(world, entity2, (ChildOf,)) == (parent,)

    @test_throws "can't copy a dead entity" copy_entity!(world, zero_entity)
end

@testset "World copy_entity! with exchange" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        Altitude,
        ChildOf,
    )

    counter = 0
    observe!(world, OnCreateEntity; with=(Altitude,)) do entity
        @test entity._id == 4
        counter += 1
    end
    counter_rel = 0
    observe!(world, OnAddRelations, (ChildOf,)) do entity
        @test entity._id == 4
        counter_rel += 1
    end

    parent = new_entity!(world, ())

    entity = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
    entity2 =
        copy_entity!(world, entity; add=(Altitude(5), ChildOf()), remove=(Position,), relations=(ChildOf => parent,))
    @test counter == 1
    @test counter_rel == 1

    @test entity2._id == entity._id + 1
    @test has_components(world, entity2, (Position,)) == false

    vel, alt = get_components(world, entity2, (Velocity, Altitude))
    @test vel == Velocity(3, 4)
    @test alt == Altitude(5)
end

@testset "World copy_entity! copy modes" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        NoIsBits,
        MutableComponent,
        MutableNoIsBits;
        allow_mutable=true,
    )

    e1 = new_entity!(
        world,
        (
            Position(0, 0),
            Velocity(0, 0),
            NoIsBits([]),
            MutableComponent(1),
            MutableNoIsBits([MutableComponent(1)]),
        ),
    )
    mut1, mut_ni1 = get_components(world, e1, (MutableComponent, MutableNoIsBits))

    e2 = copy_entity!(world, e1)
    mut2, mut_ni2 = get_components(world, e2, (MutableComponent, MutableNoIsBits))
    @test mut1 !== mut2
    @test mut_ni1 !== mut_ni2
    @test mut_ni1.v[1] === mut_ni2.v[1]

    e2 = copy_entity!(world, e1; mode=:ref)
    mut2, mut_ni2 = get_components(world, e2, (MutableComponent, MutableNoIsBits))
    @test mut1 === mut2
    @test mut_ni1 === mut_ni2
    @test mut_ni1.v[1] === mut_ni2.v[1]

    e2 = copy_entity!(world, e1; mode=:copy)
    mut2, mut_ni2 = get_components(world, e2, (MutableComponent, MutableNoIsBits))
    @test mut1 !== mut2
    @test mut_ni1 !== mut_ni2
    @test mut_ni1.v[1] === mut_ni2.v[1]

    e2 = copy_entity!(world, e1; mode=:deepcopy)
    mut2, mut_ni2 = get_components(world, e2, (MutableComponent, MutableNoIsBits))
    @test mut1 !== mut2
    @test mut_ni1 !== mut_ni2
    @test mut_ni1.v[1] !== mut_ni2.v[1]

    @test_throws(
        "ArgumentError: :foobar is not a valid copy mode, must be :ref, :copy or :deepcopy",
        copy_entity!(world, e1; mode=:foobar)
    )
end

@testset "World new_entities! with types" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        Altitude,
    )

    new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    e = new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    remove_entity!(world, e)

    cnt = 0
    new_entities!(world, 0, (Position, Velocity)) do (ent, pos_col, vel_col)
        cnt += length(ent)
    end

    new_entities!(world, 100, (Position, Velocity)) do (ent, pos_col, vel_col)
        @test length(ent) == 100
        @test length(pos_col) == 100
        @test length(vel_col) == 100
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            pos_col[i] = Position(i + 1, i + 1)
            vel_col[i] = Velocity(i + 1, i + 1)
            cnt += 1
        end
        @test is_locked(world) == true
    end

    @test cnt == 100
    @test is_locked(world) == false
    @test length(world._tables[2].entities) == 101
    @test length(world._storages[offset_ID+2].data[2]) == 101
    @test length(world._storages[offset_ID+3].data[2]) == 101

    cnt = 0
    for (ent, pos_col, vel_col) in Query(world, (Position, Velocity))
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            @test pos_col[i] == Position(i, i)
            cnt += 1
        end
    end
    @test cnt == 101
end

@testset "World new_entities! with values" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        Altitude,
    )

    new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    e = new_entity!(world, (Position(1, 1), Velocity(3, 4)))
    remove_entity!(world, e)

    count = 0
    new_entities!(world, 0, (Position(99, 99), Velocity(99, 99))) do (ent, pos_col, vel_col)
        count += length(ent)
    end
    new_entities!(world, 0, (Position(99, 99), Velocity(99, 99)))
    new_entities!(world, 0, ())

    new_entities!(world, 100, (Position(99, 99), Velocity(99, 99))) do (ent, pos_col, vel_col)
        @test length(ent) == 100
        @test length(pos_col) == 100
        @test length(vel_col) == 100
        @test pos_col isa FieldViewable
        @test vel_col isa _StructArrayView
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            @test pos_col[i] == Position(99, 99)
            @test vel_col[i] == Velocity(99, 99)
            pos_col[i] = Position(i + 1, i + 1)
            vel_col[i] = Velocity(i + 1, i + 1)
            count += 1
        end
        @test is_locked(world) == true
    end
    @test count == 100
    @test is_locked(world) == false
    @test length(world._tables[2].entities) == 101
    @test length(world._storages[offset_ID+2].data[2]) == 101
    @test length(world._storages[offset_ID+3].data[2]) == 101

    count = 0
    for (ent, pos_col, vel_col) in Query(world, (Position, Velocity))
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            @test pos_col[i] == Position(i, i)
            count += 1
        end
    end
    @test count == 101

    new_entities!(world, 100, (Position(13, 13), Velocity(13, 13)))
    @test is_locked(world) == false

    count = 0
    for (ent, pos_col, vel_col) in Query(world, (Position, Velocity))
        for i in eachindex(ent)
            @test is_alive(world, ent[i]) == true
            if i <= 101
                @test pos_col[i] == Position(i, i)
            else
                @test pos_col[i] == Position(13, 13)
            end
            count += 1
        end
    end
    @test count == 201

    new_entities!(world, 100, ()) do (ent,)
        @test length(ent) == 100
    end
end

@testset "World new_entities! with relations" begin
    world = World(
        Dummy,
        Position,
        ChildOf,
    )
    parent = new_entity!(world, ())

    new_entities!(world, 100, (Position, ChildOf); relations=(ChildOf => parent,)) do (_, positions, children)
        for i in eachindex(positions, children)
            positions[i] = Position(1, 1)
            children[i] = ChildOf()
        end
    end

    new_entities!(world, 100, (Position(0, 0), ChildOf()); relations=(ChildOf => parent,))

    for (entities, children) in Query(world, (ChildOf,))
        for i in eachindex(entities)
            parents = get_relations(world, entities[i], (ChildOf,))
            @test parents == (parent,)
        end
    end
end

@static if RUN_JET
    @testset "World new_entities! JET" begin
        world = World(
            Position,
            Velocity => Storage{StructArray},
        )
        using FunctionWrappers
        excluded = Set([
            FunctionWrappers.gen_fptr,
            Base.unsafe_convert,
            Base.setproperty!,
        ])
        function_filter(@nospecialize f) = !(f in excluded)

        #@test_opt function_filter = function_filter new_entities!(world, 100, (Position, Velocity))
        @test_opt function_filter = function_filter new_entities!(world, 100, (Position(13, 13), Velocity(13, 13)))
    end
end

@testset "World add/remove components" begin
    world = World(
        Dummy,
        Position,
        Velocity => Storage{StructArray},
        Altitude,
        Health,
    )

    e1 = new_entity!(world, ())
    add_components!(world, e1, (Position(1, 2), Velocity(3, 4)))

    e2 = new_entity!(world, (Position(5, 6), Velocity(7, 8)))

    add_components!(world, e1, (Altitude(1), Health(2)))
    add_components!(world, e2, (Altitude(3), Health(4)))

    pos, vel, a, h = get_components(world, e1, (Position, Velocity, Altitude, Health))
    @test pos == Position(1, 2)
    @test vel == Velocity(3, 4)
    @test a == Altitude(1)
    @test h == Health(2)

    @test has_components(world, e1, (Position, Velocity)) == true

    pos, vel, a, h = get_components(world, e2, (Position, Velocity, Altitude, Health))
    @test pos == Position(5, 6)
    @test vel == Velocity(7, 8)
    @test a == Altitude(3)
    @test h == Health(4)

    remove_components!(world, e1, (Position, Velocity))
    @test has_components(world, e1, (Position, Velocity)) == false

    @test_throws("ArgumentError: can't set components of a dead entity",
        set_components!(world, zero_entity, (Position(1, 2), Velocity(3, 4))))
    @test_throws("ArgumentError: can't add components to a dead entity",
        add_components!(world, zero_entity, (Position(1, 2), Velocity(3, 4))))
    @test_throws("ArgumentError: can't remove components from a dead entity",
        remove_components!(world, zero_entity, (Position, Velocity)))
    @test_throws("ArgumentError: can't check components of a dead entity",
        has_components(world, zero_entity, (Position, Velocity)))
end

@testset "Issue #430" begin
    world = World(Position, Velocity)

    entity1 = new_entity!(world, (Position(1.0, 2.0), Velocity(3.0, 4.0)))
    entity2 = new_entity!(world, (Position(5.0, 6.0), Velocity(7.0, 8.0)))

    @test get_components(world, entity1, (Position, Velocity)) == (Position(1.0, 2.0), Velocity(3.0, 4.0))
    @test get_components(world, entity2, (Position, Velocity)) == (Position(5.0, 6.0), Velocity(7.0, 8.0))

    remove_components!(world, entity1, (Position,))

    @test get_components(world, entity1, (Velocity,)) == (Velocity(3.0, 4.0),)
    @test get_components(world, entity2, (Position, Velocity)) == (Position(5.0, 6.0), Velocity(7.0, 8.0))

    remove_components!(world, entity1, (Velocity,))

    @test get_components(world, entity1, ()) == ()
    @test get_components(world, entity2, (Position, Velocity)) == (Position(5.0, 6.0), Velocity(7.0, 8.0))

    remove_components!(world, entity2, (Position,))

    @test get_components(world, entity1, ()) == ()
    @test get_components(world, entity2, (Velocity,)) == (Velocity(7.0, 8.0),)

    remove_components!(world, entity2, (Velocity,))

    @test get_components(world, entity1, ()) == ()
    @test get_components(world, entity2, ()) == ()
end

@testset "World add/remove components with relations" begin
    world = World(
        Dummy,
        Position,
        Velocity,
        ChildOf,
        ChildOf2,
    )

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    e1 = new_entity!(world, ())

    add_components!(world, e1, (Position(1, 2), ChildOf()); relations=(ChildOf => parent1,))
    @test get_relations(world, e1, (ChildOf,)) == (parent1,)

    add_components!(world, e1, (ChildOf2(),); relations=(ChildOf2 => parent2,))
    @test get_relations(world, e1, (ChildOf, ChildOf2)) == (parent1, parent2)
    @test get_relations(world, e1, (ChildOf2, ChildOf)) == (parent2, parent1)

    remove_components!(world, e1, (Position,))
    @test get_relations(world, e1, (ChildOf, ChildOf2)) == (parent1, parent2)

    remove_components!(world, e1, (ChildOf,))
    @test has_components(world, e1, (ChildOf,)) == false
    @test get_relations(world, e1, (ChildOf2,)) == (parent2,)

    add_components!(world, e1, (Position(0, 0),))
    @test get_relations(world, e1, (ChildOf2,)) == (parent2,)

    @test_throws(
        "ArgumentError: relation targets must be fully specified",
        add_components!(world, e1, (ChildOf(),)),
    )
    @test_throws(
        "ArgumentError: relation targets must be fully specified",
        add_components!(world, e1, (Velocity(0, 0), ChildOf())),
    )

    # test with recycled table
    remove_entity!(world, parent1)
    @test_throws(
        "ArgumentError: relation targets must be fully specified",
        add_components!(world, e1, (ChildOf(),)),
    )
end

@testset "World add/remove components batch" begin
    world = World(
        Dummy,
        Position => Storage{StructArray},
        Velocity,
        Altitude,
        Health,
        LabelComponent,
    )

    new_entities!(world, 10, (Position(1, 1), Velocity(1, 1), Altitude(100)))
    new_entities!(world, 10, (Position(1, 1), Velocity(1, 1), Health(100)))

    filter1 = Filter(world, (Health,))
    remove_components!(world, filter1, (Health,))

    @test count_entities(filter1) == 0

    filter2 = Filter(world, (Altitude,))
    remove_components!(world, filter2, (Altitude,)) do entities
        @test length(entities) == 10
    end

    filter3 = Filter(world, (Velocity,))
    add_components!(world, filter3, (Altitude(100),)) do (entities, altitudes)
        @test length(entities) == 20
        @test length(altitudes) == 20
        for i in eachindex(entities, altitudes)
            @test altitudes[i] == Altitude(100)
        end
    end

    add_components!(world, filter3, (LabelComponent(),))

    add_components!(world, filter3, (Health,)) do (entities, healths)
        for i in eachindex(entities, healths)
            healths[i] == Health(99)
        end
    end

    filter = Query(world, (Position, Velocity, Altitude, Health, LabelComponent))
    @test count_entities(filter) == 20
end

@static if RUN_JET
    @testset "World add/remove component JET" begin
        world = World(
            Dummy,
            Position,
            Velocity => Storage{StructArray},
        )
        using FunctionWrappers
        excluded = Set([
            FunctionWrappers.gen_fptr,
            Base.unsafe_convert,
            Base.setproperty!,
        ])
        function_filter(@nospecialize f) = !(f in excluded)

        e1 = new_entity!(world, ())
        @test_opt function_filter = function_filter add_components!(world, e1, (Position(1, 2), Velocity(3, 4)))
        #@test_opt function_filter = function_filter has_components(world, e1, (Position, Velocity))
        #@test_opt function_filter = function_filter remove_components!(world, e1, (Position, Velocity))
    end
end

@testset "World exchange components" begin
    world = World(Dummy, Position, Velocity, Altitude, Health)

    e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))

    exchange_components!(world, e1; add=(Altitude(1),), remove=(Position,))
    alt, = get_components(world, e1, (Altitude,))
    @test alt == Altitude(1)
    @test has_components(world, e1, (Position,)) == false

    exchange_components!(world, e1; add=(Health(5),))
    h, = get_components(world, e1, (Health,))
    @test h == Health(5)

    exchange_components!(world, e1; remove=(Velocity,))
    @test has_components(world, e1, (Velocity,)) == false

    @test_throws("ArgumentError: can't exchange components on a dead entity",
        exchange_components!(world, zero_entity; add=(Altitude(1),), remove=(Position,)))

    @test_throws("either components to add or to remove must be given for exchange_components!",
        exchange_components!(world, e1))
end

@testset "World exchange components with relations" begin
    world = World(Dummy, ChildOf, Position, Velocity)

    parent = new_entity!(world, ())
    e1 = new_entity!(world, (Position(1, 1), Velocity(1, 1)))
    exchange_components!(world, e1; remove=(Velocity,), add=(ChildOf(),), relations=(ChildOf => parent,))

    parents = get_relations(world, e1, (ChildOf,))
    @test parents == (parent,)
end

@testset "World exchange components batch" begin
    world = World(
        Dummy,
        Position => Storage{StructArray},
        Velocity,
        Altitude,
        Health => Storage{StructArray},
    )

    new_entities!(world, 10, (Position(1, 1), Altitude(100)))
    new_entities!(world, 10, (Position(1, 1), Velocity(1, 1)))

    # create empty table
    remove_entity!(world, new_entity!(world, (Position(1, 1), Velocity(1, 1), Altitude(100))))

    filter1 = Filter(world, (Velocity,); register=true) # register, to include empty tables.
    count = 0
    exchange_components!(world, filter1; add=(Altitude(101),), remove=(Velocity,)) do (entities, altitudes)
        @test length(entities) == 10
        @test length(altitudes) == 10
        for i in eachindex(entities, altitudes)
            @test altitudes[i] == Altitude(101)
            count += 1
        end
    end
    @test count == 10

    filter2 = Filter(world, (Position,))
    exchange_components!(world, filter2; add=(Health(101),), remove=(Position,))

    @test count_entities(filter2) == 0

    count = 0
    for (entities, healths) in Query(world, (Health,))
        for i in eachindex(entities, healths)
            @test healths[i] == Health(101)
            count += 1
        end
    end
    @test count == 20

    filter3 = Filter(world, (Altitude,))
    exchange_components!(world, filter3; add=(Position,), remove=(Altitude,)) do (entities, positions)
        for i in eachindex(entities, positions)
            positions[i] = Position(i, i)
        end
    end

    count = 0
    for (entities, positions) in Query(world, (Position,))
        for i in eachindex(entities, positions)
            @test positions[i] == Position(i, i)
            count += 1
        end
    end
    @test count == 20
end

"""
@static if RUN_JET
    @testset "World exchange component JET" begin
        world = World(Dummy, Position, Velocity, Altitude, Health)

        using FunctionWrappers
        excluded = Set([
            FunctionWrappers.gen_fptr,
            Base.unsafe_convert,
            Base.setproperty!,
        ])
        function_filter(@nospecialize f) = !(f in excluded)

        ex = (e::Entity) -> exchange_components!(world, e; add=(Altitude(1),), remove=(Position,))

        e1 = new_entity!(world, (Position(1, 2), Velocity(3, 4)))
        @test_opt function_filter = function_filter ex(e1)
    end
end
"""

@testset "remove_entity! Tests" begin
    world = World(Dummy, Position, Velocity)

    e1 = new_entity!(world, (Position(1, 1), Velocity(1, 1)))
    e2 = new_entity!(world, (Position(2, 2), Velocity(1, 1)))
    e3 = new_entity!(world, (Position(3, 3), Velocity(1, 1)))

    remove_entity!(world, e2)
    @test is_alive(world, e1) == true
    @test is_alive(world, e2) == false
    @test is_alive(world, e1) == true

    pos, = get_components(world, e1, (Position,))
    @test pos == Position(1, 1)

    pos, = get_components(world, e3, (Position,))
    @test pos == Position(3, 3)

    @test_throws("ArgumentError: can't remove a dead entity",
        remove_entity!(world, zero_entity))
end

@testset "remove_entities! Tests" begin
    world = World(Dummy, Position, Velocity, Altitude, ChildOf)

    count = 0
    obs1 = observe!(world, OnRemoveEntity) do entity
        @test is_locked(world) == true
        @test is_alive(world, entity) == true
        count += 1
    end
    count_rel = 0
    obs2 = observe!(world, OnRemoveRelations) do entity
        @test is_locked(world) == true
        @test is_alive(world, entity) == true
        count_rel += 1
    end
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    e1 = new_entity!(world, (Position(1, 1),))
    e2 = new_entity!(world, (Velocity(1, 1),))
    e3 = new_entity!(world, (Position(2, 2), Velocity(1, 1)))

    filter1 = Filter(world, (Position, Velocity))
    remove_entities!(world, filter1)

    @test is_alive(world, e1) == true
    @test is_alive(world, e2) == true
    @test is_alive(world, e3) == false
    @test count == 1
    @test count_rel == 0

    @test length(world._tables[4].entities) == 0

    entities1 = Entity[]
    new_entities!(world, 10,
        (Position(0, 0), Velocity(0, 0), ChildOf());
        relations=(ChildOf => parent1,),
    ) do (entities, _, _, _)
        append!(entities1, entities)
    end

    entities2 = Entity[]
    new_entities!(world, 10,
        (Position(0, 0), Velocity(0, 0), ChildOf());
        relations=(ChildOf => parent2,),
    ) do (entities, _, _, _)
        append!(entities2, entities)
    end

    # create an archetype without tables
    parent3 = new_entity!(world, ())
    remove_entity!(world, new_entity!(world, (Position(0, 0), ChildOf()); relations=(ChildOf => parent3,)))
    remove_entity!(world, parent3)

    filter2 = Filter(world, (ChildOf,); relations=(ChildOf => parent1,))
    remove_entities!(world, filter2)

    @test count == 13
    @test count_rel == 11

    for entity in entities1
        @test is_alive(world, entity) == false
    end

    for entity in entities2
        @test is_alive(world, entity) == true
    end

    filter3 = Filter(world, ())
    remove_entities!(world, filter3)

    @test count == 27
    @test count_rel == 21

    @test count_entities(Filter(world, ())) == 0
end

@testset "remove_entities! callback" begin
    world = World(Dummy, Position, Velocity, Altitude)

    new_entity!(world, (Position(1, 1),))
    new_entity!(world, (Position(2, 2),))

    filter = Filter(world, (Position,))

    counter = 0
    remove_entities!(world, filter) do entities
        @test is_locked(world) == true
        @test entities isa Entities
        @test length(entities) == 2
        counter += 1
    end
    @test counter == 1
end

@testset "remove_entities! cached filter" begin
    world = World(Dummy, Position, Velocity, ChildOf)
    filter = Filter(world, (Position,); register=true)

    parent = new_entity!(world, ())

    new_entity!(world, (Position(1, 1),))
    new_entity!(world, (Position(2, 2),))

    # Create an empty table
    remove_entity!(world, new_entity!(world, (Position(1, 1), Velocity(0, 0))))

    counter = 0
    remove_entities!(world, filter) do entities
        @test is_locked(world) == true
        @test entities isa Entities
        @test length(entities) == 2
        counter += 1
    end
    @test counter == 1

    @test length(filter._filter.tables) == 2

    new_entity!(world, (Position(1, 1), ChildOf()); relations=(ChildOf => parent,))
    new_entity!(world, (Position(2, 2), ChildOf()); relations=(ChildOf => parent,))

    counter = 0
    remove_entities!(world, filter) do entities
        @test is_locked(world) == true
        @test entities isa Entities
        @test length(entities) == 2
        counter += 1
    end
    @test counter == 1
end

@testset "World reset!" begin
    world = World(Dummy, Position, Velocity, ChildOf)

    obs = observe!(world, OnAddComponents, (Position,)) do _
    end

    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())
    new_entity!(world, (Position(1, 1),))
    new_entity!(world, (Velocity(1, 1),))
    new_entity!(world, (Position(1, 1), Velocity(1, 1)))
    new_entity!(world, (Position(1, 1), ChildOf()); relations=(ChildOf => parent1,))
    new_entity!(world, (Position(1, 1), ChildOf()); relations=(ChildOf => parent2,))

    filter = Filter(world, (Position,); register=true)

    reset!(world)

    @test length(world._entities) == 1
    @test length(world._entity_pool.entities) == 1
    @test length(world._cache.filters) == 0
    @test filter._filter.id[] == 0
    @test length(filter._filter.tables) == 0

    for t in 2:6
        @test length(world._tables[t].entities) == 0
        @test length(world._tables[t].filters) == 0
    end

    for s in 2:4
        for t in 2:6
            @test length(world._storages[offset_ID+s].data[t]) == 0
        end
    end

    @test length(world._archetypes[1].tables) == 1
    @test length(world._archetypes[2].tables) == 1
    @test length(world._archetypes[3].tables) == 1
    @test length(world._archetypes[4].tables) == 1
    @test length(world._archetypes[5].tables) == 0
    @test length(world._archetypes[5].free_tables) == 2

    @test obs._id.id == 0
    @test !_has_observers(world._event_manager, OnAddComponents)

    e = new_entity!(world, (Position(1, 1),))
    @test e._id == 2
    @test e._gen == 0

    q = Query(world, ())
    @test_throws(
        "InvalidStateException: cannot modify a locked world: " *
        "collect entities into a vector and apply changes after query iteration has completed",
        reset!(world))

    close!(q)
    reset!(world)
end

@testset "World relations index" begin
    world = World(Dummy, ChildOf, Position, Velocity, ChildOf2)
    parent1 = new_entity!(world, ())
    parent2 = new_entity!(world, ())

    new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent1,))
    new_entity!(world, (Position(0, 0), Velocity(0, 0), ChildOf()); relations=(ChildOf => parent2,))
    new_entity!(world, (Position(0, 0), ChildOf2(), ChildOf()); relations=(ChildOf => parent1, ChildOf2 => parent2))
    new_entity!(world, (Position(0, 0), ChildOf2(), ChildOf()); relations=(ChildOf => parent2, ChildOf2 => parent1))

    pos_relations = _get_relations_storage(world, Position)
    child_relations = _get_relations_storage(world, ChildOf)
    child2_relations = _get_relations_storage(world, ChildOf2)

    @test length(pos_relations.archetypes) == 0
    @test length(pos_relations.targets) == 0

    @test length(child_relations.archetypes) == 3
    @test length(child_relations.targets) == 5
    @test child_relations.archetypes[1] == 0
    @test child_relations.archetypes[2] == 1
    @test child_relations.archetypes[3] == 1

    @test child_relations.targets[1] == _no_entity
    @test child_relations.targets[2] == parent1
    @test child_relations.targets[3] == parent2
    @test child_relations.targets[4] == parent1
    @test child_relations.targets[5] == parent2

    @test length(child2_relations.archetypes) == 3
    @test length(child2_relations.targets) == 5
    @test child2_relations.archetypes[1] == 0
    @test child2_relations.archetypes[2] == 0
    @test child2_relations.archetypes[3] == 2

    @test child2_relations.targets[1] == _no_entity
    @test child2_relations.targets[2] == _no_entity
    @test child2_relations.targets[3] == _no_entity
    @test child2_relations.targets[4] == parent2
    @test child2_relations.targets[5] == parent1

    @test world._archetypes[1].num_relations == 0
    @test world._archetypes[2].num_relations == 1
    @test world._archetypes[3].num_relations == 2
end

@testset "World add/remove resources Tests" begin
    world = World(Dummy, Position, Velocity)

    @test has_resource(world, Tick) == false

    add_resource!(world, Tick(0))
    @test has_resource(world, Tick) == true
    res = get_resource(world, Tick)
    @test res isa Tick && res.time == 0
    @test_throws "ArgumentError: World already contains a resource of type Tick" add_resource!(world, Tick(1))
    @inferred Tick get_resource(world, Tick)

    set_resource!(world, Tick(2))
    res = get_resource(world, Tick)
    @test res isa Tick && res.time == 2

    remove_resource!(world, Tick)
    @test has_resource(world, Tick) == false
    @test_throws "KeyError: key Tick not found" get_resource(world, Tick)

    @test_throws "ArgumentError: World does not contain a resource of type Tick" set_resource!(world, Tick(2))
end

@static if RUN_JET
    @testset "Resources JET" begin
        world = World()

        f = () -> begin
            _ = has_resource(world, Tick)
            add_resource!(world, Tick(0))
            _ = has_resource(world, Tick)
            _ = get_resource(world, Tick)
            set_resource!(world, Tick(2))
            remove_resource!(world, Tick)
        end

        @test_opt f()
    end
end
