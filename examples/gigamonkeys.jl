# The example from chapter 19 of "Practical Common Lisp"

using Conditions

# Some stuff missing in the original text

struct LogEntry
    text
end

function is_well_formed_log_entry(txt)
    !ismissing(txt) && isnothing(match(r"invalid", txt))
end

function analyze_entry(entry)
    println("Analyzing entry: $entry")
end

function find_all_logs()
    # Some demo data
    [["Text ...", "More Text", "invalid"],
     ["Text 2", missing, "Text 3", "Text 4"]]
end

# The original example

struct MalformedLogEntryException <: Exception
    text
end

function parse_log_entry(txt)
    if is_well_formed_log_entry(txt)
        LogEntry(txt)
    else
        @restart_case @signal(MalformedLogEntryException(txt)) begin
            :use_value => value -> value
            :reparse_entry => fixed_text -> parse_log_entry(fixed_text)
        end
    end
end

function parse_log_file(file)
    stuff = []
    for txt in file
        let entry = (@restart_case parse_log_entry(txt) begin
                         :skip_log_entry => () -> nothing
                     end)
            if !isnothing(entry)
                push!(stuff, entry)
            end
        end
    end
    stuff
end

function log_analyzer()
    for log in find_all_logs()
        analyze_log(log)
    end
end

function analyze_log(log)
    for entry in parse_log_file(log)
        analyze_entry(entry)
    end
end

function skip_log_entry(c)
    let restart = find_restart(:skip_log_entry)
        if !isnothing(restart)
            invoke_restart(restart)
        end
    end
end

function skipping_log_analyzer()
    handler_bind(Handler(MalformedLogEntryException, skip_log_entry)) do
        for log in find_all_logs()
            analyze_log(log)
        end
    end
end

struct MalformedLogEntry
    stuff
end

function nonskipping_log_analyzer()
    handler_bind(Handler(MalformedLogEntryException,
                         c -> invoke_restart(find_restart(:use_value),
                                             MalformedLogEntry(c.text)))) do
        for log in find_all_logs()
            analyze_log(log)
        end
    end
end

function fixing_log_analyzer()
    handler_bind(Handler(MalformedLogEntryException,
                         c -> invoke_restart(find_restart(:reparse_entry), "FIXED"))) do
        for log in find_all_logs()
            analyze_log(log)
        end
    end
end
