
@testset "debug flag" begin
    @test Ark.DEBUG == "true"
end

@testset "_format_type" begin
    @test _format_type(Int64) == "Int64"
    @test _format_type(Position) == "Position"
    @test _format_type(CompN{Int64}) == "CompN{Int64}"
    @test _format_type(CompN{CompN{Int64}}) == "CompN{CompN{Int64}}"
    @test _format_type(CompN{CompN{CompN{Int64}}}) == "CompN{CompN{CompN{Int64}}}"
end
