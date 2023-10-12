module Conditions

using Infiltrator
using ScopedValues

# Simple immutable stack type

abstract type Stack{T}
end

struct Empty{T} <: Stack{T}
end

struct Top{T} <: Stack{T}
    top::T
    below::Stack{T}
end

function put(x::T, s::Stack{T}) where {T}
    Top{T}(x, s)
end

function isempty(s::Empty)
    true
end
function isempty(s::Stack)
    false
end

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

const handler_stack = ScopedValue{Stack{Any}}(Empty{Any}())

function get_handlers()
    handler_stack[]
end

function with_handlers(body, stack)
    with(body, handler_stack => stack)
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
function toggle_interactive(b::Bool)
    handle_interactive[] = b
end
    
function signal(condition)
    # Just run all matching handlers here
    # Note: Handler stack is stored as nested pairs used like a nothing terminated list!
    stack = get_handlers()
    while !isempty(stack)
        with_handlers(stack.below) do
            for handler in stack.top
                if condition isa handler.type
                    handler.fun(condition)
                end
            end
        end
        stack = stack.below
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
    with_handlers(body, put(handlers, get_handlers()))
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
    types = [esc(spec.args[2]) for spec in handler_block.args if spec isa Expr]
    funs = [esc(spec.args[3]) for spec in handler_block.args if spec isa Expr]
    tag = QuoteNode(gensym("tag"))
    handlers = [:(Handler($(type), c -> jump($(esc(tag)), ($(i), c))))
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

# Restarts

"""
    Restart(name::Symbol, fun)

Create a restart with the given `name` and function `fun`.
"""
struct Restart{F}
    name::Symbol
    fun::F
end

const restart_stack = ScopedValue{Stack{Any}}(Empty{Any}())

function get_restarts()
    restart_stack[]
end

function with_restarts(body, stack)
    with(body, restart_stack => stack)
end

"""
    invoke_restart(restart::Restart, args...)

Call the function of `restart` with the given `args`.
"""
function invoke_restart(restart::Restart, args...)
    restart.fun(args...)
end

# function compute_restarts()
#     # Flattens restart stack
#     Iterators.flatmap(first,
#                       IterTools.takewhile((!) ∘ isnothing,
#                                           IterTools.iterated(last, get_restarts())))
# end

"""
    find_restart(name::Symbol)

Find a restart with this `name`. If multiple restarts with the same name are
active only the most recently established one is found.
Returns nothing if no restart with this name is available.
"""
function find_restart(name::Symbol)
    stack = get_restarts()
    while !isempty(stack)
        for restart in stack.top
            if restart.name == name
                return restart
            end
        end
        stack = stack.below
    end
    return nothing
end

"""
    restart_bind(body, restarts::Restart...)

Establishes restarts and runs `body`.
When `body` returns normally, its result is returned.
When `body` signals a condition, a signal handler can decide to invoke
one of the available restarts.

Note: Low level function. More often than not, [`@restart_case`](@ref) is what you want.
"""
function restart_bind(body, restarts::Restart...)
    with_restarts(body, put(restarts, get_restarts()))
end

"""
Convenience macro around [`restart_bind`](@ref) which unwinds the stack
before running a restart.

Note: If a handler wants to run a restart higher-up in the stack this has
      to be done within `handler_bind`, i.e., without unwinding the stack

# Example
```julia-repl
julia> handler_bind(Handler(Any, c -> invoke_restart(find_restart(:myrestart), 2 * c))) do
           @restart_case @signal(3) begin
               :myrestart => c -> c + 1
           end
       end
7
```
"""
macro restart_case(expr, restart_block)
    names = [esc(spec.args[2]) for spec in restart_block.args if spec isa Expr]
    funs = [esc(spec.args[3]) for spec in restart_block.args if spec isa Expr]
    tag = QuoteNode(gensym("tag"))
    restarts = [:(Restart($(name), (args...) -> jump($(esc(tag)), ($(i), args))))
                for (i, name) in enumerate(names)]
    quote
        let (i, res) = (nonlocal($(esc(tag))) do
                            restart_bind($(restarts...)) do
                                (0, $(esc(expr)))
                            end
                        end)
            if iszero(i)
                res
            else
                [$(funs...)][i](res...)
            end
        end
    end
end

# Exported public API

export nonlocal, jump

export Handler, NoMatchingHandler
export toggle_interactive, @signal, handler_bind, @handler_case
export Restart, find_restart, invoke_restart, restart_bind, @restart_case

end # module Conditions
