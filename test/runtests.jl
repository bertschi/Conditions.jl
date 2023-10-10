using Conditions

using Test

@testset "Non-local jump" begin
    g(x) = jump(:hop, 2*x)
    @test 6 == nonlocal(:hop) do
        1 + g(3)
    end
end

@testset "Condition handling" begin
    toggle_interactive(false)
    myerr = ArgumentError("test")
    myval = :test_that
    myhandler = Handler(ArgumentError, c -> jump(:here, c))
    @test myval == nonlocal(:here) do
        handler_bind(myhandler) do
            myval
        end
    end
    @test myerr == nonlocal(:here) do
        handler_bind(myhandler) do
            @signal myerr
        end
    end
    @test_throws NoMatchingHandler handler_bind(myhandler) do
        @signal "This is no error"
    end
    # Test multiple handlers
    tmp = []
    @test_throws NoMatchingHandler handler_bind(
        Handler(String, s -> push!(tmp, "First: " * s)),
        Handler(Any, s -> push!(tmp, "Second: " * s))) do
            handler_bind(Handler(String, s -> push!(tmp, "Inner: " * s))) do
                @signal "Error"
            end
        end
    @test tmp == ["Inner: Error", "First: Error", "Second: Error"]
    # Just like the example of handler_bind
    empty!(tmp)
    g(x) = @signal 2*x
    res = nonlocal(:out) do
        handler_bind(Handler(Number, c -> push!(tmp, (:match, c))),
                     Handler(Vector, c -> push!(tmp, (:nonmatch, c))),
                     Handler(Int64, c -> begin push!(tmp, (:again, c)); jump(:out, c + 2) end),
                     Handler(Any, c -> push!(tmp, (:never, c)))) do
            g(3)
       end
    end
    @test res == 8
    @test tmp == [(:match, 6), (:again, 6)]
    # Finally, handler_case
    @test :ha == @handler_case :ha begin
        Integer => c -> (:integer, c)
        Number => c -> (:number, c)
        Any => c -> (:any, c)
    end
    @test (:number, 3.0) == @handler_case @signal(3.0) begin
        Integer => c -> (:integer, c)
        Number => c -> (:number, c)
        Any => c -> (:any, c)
    end
end
