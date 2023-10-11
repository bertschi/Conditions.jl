# Conditions.jl

Common Lisp like condition system for Julia

Start with the docstring of `@handler_case` to see how this works ...
```julia-repl
help?> @handler_case
  Convenience macro around handler_bind which works similar to try-catch, i.e., the first matching handler is run with the stack unwound and its result is returned.

  Examples
  ≡≡≡≡≡≡≡≡≡≡

  julia> @handler_case @signal(3.0) begin
             Integer => c -> (:integer, c)
             Number => c -> (:number, c)
             Any => c -> (:any, c)
         end
  (:number, 3.0)

  See also @signal, handler_bind as well as nonlocal and jump.
```

**Features**

* `@signal` does not unwind the stack, i.e., in contrast to `throw`

* Restarts allow to continue execution higher up in the stack

**Thinks to try**

Use interactive setup and drop into `Infiltrator` where a condition was signalled!

```julia
using Conditions

toggle_interactive(true)

h(z) = @signal z
g(y) = h(y + 2)
f(x) = g(2 * x)

f(3)
# Try @trace and @locals from the infiltration prompt! 
```

Restarts are the real deal and allow top-level code decide how to
fix stuff higher up on the stack!

```julia
using Conditions

function nonneg(x::Number)
    if x >= 0
        x
    else
        @signal ArgumentError("Negative $x")
    end
end

function validate(x::Number)
    @restart_case nonneg(x) begin
        :fix_value => newval -> newval
    end
end

function mysum(xs::AbstractVector)
    @restart_case sum(validate, xs) begin
        :rough_guess => () -> 42
    end
end

# Restart functions
function fix_value(condition)
    fixme = find_restart(:fix_value)
    if !isnothing(fixme)
        fixval = 2
        println("Fixing $(condition.msg) into $fixval")
        invoke_restart(fixme, fixval)
    end
end

function rough_guess(condition)
    guess = find_restart(:rough_guess)
    if !isnothing(guess)
        println("Guessing total after $condition")
        invoke_restart(guess)
    end
end

xs = [1, 2, -1, 3, 4, -5, 0]

# Top-level handler decides what to do
handler_bind(Handler(ArgumentError, fix_value)) do
    mysum(xs)
end

handler_bind(Handler(ArgumentError, rough_guess)) do
    mysum(xs)
end
```
