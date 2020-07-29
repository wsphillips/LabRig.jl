
module RemoteNIDAQ

using ..Distributed, ..DataStructures

global NIDAQ_PID

export RemoteRecording, stage, start_recording

struct RemoteRecording
    channels::Dict{Int64, String}
    fs::Int64
    refresh::Float64
    history_seconds::Float64
    history_samples::Int64
    signal::CircularBuffer{Float64}
    r_chan::RemoteChannel{Channel{Array{Float64,1}}}

    function RemoteRecording(; channels = Dict(2 => "XII", 3 => "Vm"), fs = 20000, refresh = 50, history_seconds = 8)
        history_samples = history_seconds * fs * channels
        signal = CircularBuffer{Float64}(history_samples)
        fill!(signal, 0.0)
        r_chan = RemoteChannel(() -> Channel{Vector{Float64}}(500), NIDAQ_PID)    
        new(channels, fs, refresh, history_seconds, history_samples, signal, r_chan)
    end
end

function init(pid)
    if !@isdefined NIDAQ_PID
        global NIDAQ_PID = pid
    end
    wait(@spawnat pid @eval using NIDAQ)
end

function stage(rec::RemoteRecording)
    pid = NIDAQ_PID
    @sync begin
        @spawnat pid @eval (result = Float64[]; dev = DefaultDev(); task = DAQTask{AI}())
        for (chan, name) in rec.channels
            @spawnat pid append!(task, dev.channels[AI][chan], alias = name, tcfg = DAQmx.Diff, range = (-1.0,1.0))
        end
    end
    return
end

function start_recording(rec::RemoteRecording)
    # record!
    wait(@spawnat nidaq_pid record!(result, task; remote = rec.r_chan))
end

end # module

