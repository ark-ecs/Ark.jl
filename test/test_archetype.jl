
@testset "_IdCollection" begin
    t1 = _new_table(Val(1), UInt32(1), UInt32(1))
    t2 = _new_table(Val(1), UInt32(2), UInt32(1))
    t3 = _new_table(Val(1), UInt32(3), UInt32(1))
    t4 = _new_table(Val(1), UInt32(4), UInt32(1))
    t5 = _new_table(Val(1), UInt32(5), UInt32(1))
    t6 = _new_table(Val(1), UInt32(6), UInt32(1))

    @test length(t1) == 0
    @test isempty(t1) == true

    ids = _IdCollection(t5.id, t4.id, t3.id, t2.id, t1.id)

    @test ids.ids == [t5.id, t4.id, t3.id, t2.id, t1.id]
    @test ids[1] == 5
    @test ids[5] == 1
    @test ids.indices[5] == 1
    @test ids.indices[1] == 5

    _add_id!(ids, t6.id)
    @test ids.ids == [t5.id, t4.id, t3.id, t2.id, t1.id, t6.id]
    @test ids.indices[6] == 6

    @test _remove_id!(ids, t3.id) == true
    @test ids.ids == [t5.id, t4.id, t6.id, t2.id, t1.id]
    @test ids.indices[6] == 3

    @test _remove_id!(ids, t1.id) == true
    @test ids.ids == [t5.id, t4.id, t6.id, t2.id]
    @test ids.indices[6] == 3

    @test _remove_id!(ids, t1.id) == false
    @test ids.ids == [t5.id, t4.id, t6.id, t2.id]
    @test ids[3] == 6
    @test ids.indices[6] == 3
end

@testset "_Archetype _add_table!" begin
    # TODO: re-activate, but use world and entity creations
    """
    world = World(Dummy, Position, ChildOf)
    child_id = 3 + offset_ID

    t1 =
        _find_or_create_table!(
            world,
            world._tables[1],
            (2 + offset_ID, child_id),
            (),
            (child_id,),
            (_new_entity(2, 1),),
        )
    t2 =
        _find_or_create_table!(
            world,
            world._tables[1],
            (2 + offset_ID, child_id),
            (),
            (child_id,),
            (_new_entity(99, 1),),
        )

    arch = world._archetypes[2]

    @test arch.relations == [child_id]
    @test length(arch.index) == 1

    index = arch.index[1]
    @test index[2].tables == [world._tables[t1]]
    @test index[99].tables == [world._tables[t2]]

    table, found = _get_table(world, arch, [child_id => _new_entity(99, 1)])
    @test found == true
    @test table == world._tables[t2]

    table, found = _get_table(world, arch, [child_id => _new_entity(101, 1)])
    @test found == false
    """
end

@testset "_Archetype has relations" begin
    world = World(Dummy, Position, ChildOf)

    new_entity!(world, (Position(0, 0),))
    @test _has_relations(world._archetypes[2]) == false

    # TODO: re-activate this
    #new_entity!(world, (ChildOf(),))
    #@test _has_relations(world._archetypes[3]) == true
end
