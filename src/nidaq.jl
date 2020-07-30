
module RemoteNIDAQ

using Distributed, DataStructures, Base.Meta

if myid() > 1
    using NIDAQ
else

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
    
        function RemoteRecording(r_chan; channels = Dict(2 => "XII", 3 => "Vm"), fs = 20000, refresh = 50, history_seconds = 8)
            history_samples = history_seconds * fs * length(channels)
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
        #remotecall_wait(Base.eval, NIDAQ_PID, Main, :(using NIDAQ))
    end
    
    function stage(rec::RemoteRecording)
        pid = NIDAQ_PID
        ex = quote
            result = Float64[]
            dev = DefaultDev()
            task = DAQTask{AI}()
        end
        @spawnat pid eval(ex)
        for (chan, name) in rec.channels
            @spawnat pid Base.append!(task, dev.channels[AI][chan], alias = name, tcfg = DAQmx.Diff, range = (-1.0,1.0))
        end
        return
    end
    
    function start_recording(rec::RemoteRecording, r_chan)
        # record!
        remotecall_wait(record!, NIDAQ_PID, result, task, remote = r_chan)
    end
end

end # module

