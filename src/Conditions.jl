module Conditions

using Infiltrator

# Simple non-local exit

struct NonLocal{T}
    tag::Symbol
    val::T
end

"""
    nonlocal(body, tag::Symbol)

Wraps `body` to catch non-local jumps to this `tag`.

# Examples
```julia-repl
julia> g(x) = jump(:hop, 2*x)
g (generic function with 1 method)

julia> nonlocal(:hop) do
           1 + g(3)
       end
6
```
See also [`jump`](@ref).
"""
function nonlocal(body, tag::Symbol)
    try
        body()
    catch e
        if isa(e, NonLocal) && e.tag == tag
            e.val
        else
            rethrow(e)
        end
    end
end

"""
    jump(tag::Symbol, val)

Throw `val` to catch under the given `tag`.

# Examples
```julia-repl
julia> g(x) = jump(:hop, 2*x)
g (generic function with 1 method)

julia> nonlocal(:hop) do
           g(3)
       end
6
```
See also [`nonlocal`](@ref).
"""
function jump(tag::Symbol, val)
    throw(NonLocal(tag, val))
end

# Dynamically bound handlers

"""
    Handler(type, fun)

Handle conditions of `type` using `fun`.
`fun` gets passed the condition as its only argument.

See also [`@signal`](@ref) and [`handler_bind`](@ref).
"""
struct Handler{T,F}
    type::T
    fun::F
end

const handler_key = gensym("handler_stack")

function get_handlers()
    store = task_local_storage()
    if haskey(store, handler_key)
        store[handler_key]
    else
        nothing
    end
end

function with_handlers(body, stack)
    task_local_storage(body, handler_key, stack)
end

struct NoMatchingHandler{C} <: Exception
    condition::C
end

handle_interactive::Ref{Bool} = Ref(true)

"""
    toggle_interactive(b::Bool)

Set if signals should be handled interactively if no matching handler can be found.

If `true` an `Infiltrator` at the point of signalling is established. 
If `false` a `NoMatchingHandler` error is thrown.
"""
toggle_interactive(b::Bool) = handle_interactive[] = b

function signal(condition)
    # Just run all matching handlers here
    # Note: Handler stack is stored as nested pairs used like a nothing terminated list!
    stack = get_handlers()
    while !isnothing(stack)
        with_handlers(last(stack)) do
            for handler in first(stack)
                if condition isa handler.type
                    handler.fun(condition)
                end
            end
        end
        stack = last(stack)
    end
end

"""
    @signal condition

Signal `condition`. Like `throw` except that the stack is not unwound.

# Examples
```julia-repl
julia> g(x) = @signal 2*x
g (generic function with 1 method)

julia> handler_bind(Handler(Any, c -> println(filter(frame -> frame.func == :g, stacktrace())))) do
           g(3)
       end
Base.StackTraces.StackFrame[g(x::Int64) at REPL[23]:1]
ERROR: NoMatchingHandler{Int64}(6)
```
See also [`handler_bind`](@ref) and [`@handler_case`](@ref).
"""
macro signal(condition)
    # Make signal a macro to @infiltrate at actual error location in interactive use
    c = esc(condition)
    quote
        signal($c)
        # Now check for interactive use or throw
        if handle_interactive[]
            @infiltrate
        else
            throw(NoMatchingHandler($c))
        end
    end
end

"""
    handler_bind(body, handlers::Handler...)

Establishes signal handlers and runs `body`.
When `body` returns normally, its result is returned.
When `body` signals a condition all handlers matching the condition type are run.

Note:

* Handlers are run before unwinding the stack, but can use non-local jumps
  to unwind and return a result.

* See [`toggle_interactive`](@ref) for the default behavior, i.e., if
  no handler decides to return non-locally.

# Examples
```julia-repl
julia> g(x) = @signal 2*x
g (generic function with 1 method)

julia> nonlocal(:out) do
           handler_bind(Handler(Number, c -> @show (:match, c)),
                        Handler(Vector, c -> @show (:nonmatch, c)),
                        Handler(Int64, c -> begin @show (:again, c); jump(:out, c + 2) end),
                        Handler(Any, c -> @show (:never, c))) do
               g(3)
           end
       end
(:match, c) = (:match, 6)
(:again, c) = (:again, 6)
8
```
"""
function handler_bind(body, handlers::Handler...)
    with_handlers(body, handlers => get_handlers())
end

"""
Convenience macro around [`handler_bind`](@ref) which works similar
to try-catch, i.e., the first matching handler is run with the stack
unwound and its result is returned.

# Examples
```julia-repl
julia> @handler_case @signal(3.0) begin
           Integer => c -> (:integer, c)
           Number => c -> (:number, c)
           Any => c -> (:any, c)
       end
(:number, 3.0)
```
See also [`@signal`](@ref), [`handler_bind`](@ref) as well as
[`nonlocal`](@ref) and [`jump`](@ref).
"""
macro handler_case(expr, handler_block)
    types = [spec.args[2] for spec in handler_block.args if spec isa Expr]
    funs = [spec.args[3] for spec in handler_block.args if spec isa Expr]
    tag = QuoteNode(gensym("tag"))
    handlers = [:(Handler($(esc(type)), c -> jump($(esc(tag)), ($(i), c))))
                for (i, type) in enumerate(types)]
    quote
        let (i, c) = (nonlocal($(esc(tag))) do
                          handler_bind($(handlers...)) do
                              (0, $(esc(expr)))
                          end
                      end)
            if iszero(i)
                c
            else
                [$(funs...)][i](c)
            end
        end
    end
end

export nonlocal, jump

export Handler, NoMatchingHandler
export toggle_interactive, @signal, handler_bind, @handler_case

end # module Conditions
