
using UniqueVectors

@testset "UniqueVector storage" begin
    w = World(Position => Storage{UniqueVector})
    e1 = new_entity!(w, (Position(1.0, 2.0),))
    e2 = new_entity!(w, (Position(3.0, 4.0),))
    e3 = new_entity!(w, (Position(5.0, 6.0),))

    idx1 = _state(w)._entities[e1._id]

    remove_entity!(w, e1)
    @test !is_alive(w, e1)
    @test is_alive(w, e2)
    @test is_alive(w, e3)
    @test _state(w)._entities[e3._id].row == idx1.row

    p2, = get_components(w, e2, (Position,))
    p3, = get_components(w, e3, (Position,))
    @test p2.x == 3.0 && p2.y == 4.0
    @test p3.x == 5.0 && p3.y == 6.0
end
