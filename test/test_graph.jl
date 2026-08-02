
@testset "_Graph functionality" begin
    # Create a graph
    graph = _Graph{1}()
    @test length(graph.nodes) == 1

    # Create a mutable mask and set a bit
    mask = _MutableMask{1}()
    _set_bit!(mask, 3)

    # Test _find_or_create: should create a new node
    node = _find_or_create(graph, mask)
    @test node.mask == _Mask(mask)
    @test node.archetype[] == typemax(UInt32)
    @test length(graph.nodes) == 2

    # Test _find_or_create again: should return existing node
    node2 = _find_or_create(graph, mask)
    @test node2 === node
    @test length(graph.nodes) == 2  # no new node added

    # Test _find_node: add and remove components
    start = graph.nodes[_Mask{1}()]
    add = (5,)
    remove = ()

    node3 = _find_node(graph, start, add, remove, _Mask{1}(add...), _Mask{1}(remove...), _NoUseMap())
    @test node3 !== start
    @test _get_bit(node3.mask, 5)

    node4 = _find_node(graph, node3, (), (5,), _Mask{1}(), _Mask{1}(5), _UseMap())
    @test node4 === start

    # Test error on removing nonexistent component
    @test_throws(
        "ArgumentError: entity does not have component to remove",
        _find_node(graph, start, (), (7,), _Mask{1}(), _Mask{1}(7), _UseMap())
    )

    # Test error on adding duplicate component
    @test_throws(
        "ArgumentError: entity already has component to add",
        _find_node(graph, node3, (5,), (), _Mask{1}(5), _Mask{1}(), _UseMap())
    )

    world = TestWorld(Position, Velocity)
    e = new_entity!(world, (Position(0.0, 0.0),))

    # Test error on adding and removing the same components
    @test_throws(
        "ArgumentError: component added and removed in the same exchange operation",
        exchange_components!(world, e; add=(Velocity(0.0, 0.0),), remove=(Velocity,))
    )

    # Test error on duplicates in adding componets
    @test_throws(
        "ArgumentError: duplicate component types: Velocity",
        add_components!(world, e, (Velocity(0.0, 0.0), Velocity(0.0, 0.0)))
    )

    # Test error on duplicates on removing components
    @test_throws(
        "ArgumentError: duplicate component types: Position",
        remove_components!(world, e, (Position, Position))
    )
end
