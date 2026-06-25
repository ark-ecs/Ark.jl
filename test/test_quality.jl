
# These tests are too slow
if RUN_JET
    using Aqua
    @testset "Aqua tests" begin
        Aqua.test_all(Ark, deps_compat=false)
        Aqua.test_deps_compat(Ark, check_extras=false)
    end

    @testset "JET tests" begin
        rep = JET.report_package(Ark, target_modules=[Ark])
        println(rep)

        reports = JET.get_reports(rep)
        is_known_false_positive(r) = begin
            msg = sprint(show, r)
            occursin(
                "ArgumentError: either components to add or to remove must be given for exchange_components!",
                msg,
            ) ||
            (occursin("_valtuple(::Tuple)", msg) && occursin("Core.TypeofVararg", msg)) ||
            (occursin("_relation_types_and_targets", msg) && occursin("Core.TypeofVararg", msg))
        end
        filtered = filter(!is_known_false_positive, reports)

        println(filtered)
        @test length(filtered) == 0
    end
end
