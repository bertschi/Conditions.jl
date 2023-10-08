using Conditions

using Test

@testset "signal condition" begin
    myerr = ArgumentError("test")
    myval = :test_that
    myhandler = Handler(ArgumentError, c -> jump(c))
    @test myval == @nonlocal begin
        handler_bind(myhandler) do
            myval
        end
    end
    @test myerr == @nonlocal begin
        handler_bind(myhandler) do
            signal(myerr)
        end
    end
    @test_throws NoMatchingHandler handler_bind(myhandler) do
        signal("This is no error")
    end
end
