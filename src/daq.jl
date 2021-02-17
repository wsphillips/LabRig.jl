module DAQ

using NIDAQ
using DataStructures
import ThreadPools.@tspawnat
import NIDAQ: pulses!, pulses, pulsetiming, pulsetiming!, start, stop
export Recording

const NIDAQ_TID = Ref{Int64}(1)

if Threads.nthreads() > 1
    NIDAQ_TID[] = 2
end

mutable struct Recording
    task::DAQTask{AI}
    channels::Dict{Int64, String}
    fs::Int64
    refresh::Float64
    history_seconds::Float64
    history_samples::Int64
    signal::CircularBuffer{Float64}
    chan::Channel
    function Recording(; channels = Dict(2 => "XII", 3 => "Vm"), fs = 20000, refresh = 50, history_seconds = 8)
        history_samples = history_seconds * fs * length(channels)
        signal = CircularBuffer{Float64}(history_samples)
        fill!(signal, 0.0)
        chan = Channel(500)
        dev = DefaultDev()
        task = DAQTask{AI}()
        for (chan, name) in channels
            push!(task, dev.channels[AI][chan], alias = name, tcfg = DAQmx.Diff, range = (-1.0,1.0))
        end
        rec = new(task, channels, fs, refresh, history_seconds, history_samples, signal, chan)
        signal_updates(rec)
        finalizer(rec) do rec
            close(rec.chan)
        end
        return rec
    end
end

mutable struct Stimulus
    task::DAQTask{CO}
    function Stimulus()
        dev = DefaultDev()
        task = DAQTask{CO}()
        source = dev.channels[CO][1]
        pulses(task, source)
        return new(task)
    end
end

function signal_updates(rec::Recording)
    @async begin
        for x in rec.chan
            append!(rec.signal, vec(x))
        end
    end
end

function (rec::Recording)()
    @tspawnat NIDAQ_TID[] record!(rec.task, $(rec.fs), $(rec.refresh); feed = rec.chan)
end

fetch_history(rec::Recording) = fetch(@tspawnat NIDAQ_TID[] collect(rec.signal))

pulsetiming!(s::Stimulus, args...) = NIDAQ.pulsetiming!(s.task, args...)
pulsetiming(s::Stimulus, args...) = NIDAQ.pulsetiming(s.task, args...)
stop(s::Stimulus) = NIDAQ.stop(s.task)

end # module
