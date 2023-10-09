using Conditions

using Test

@testset "signal condition" begin
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
            signal(myerr)
        end
    end
    @test_throws NoMatchingHandler handler_bind(myhandler) do
        signal("This is no error")
    end
end
