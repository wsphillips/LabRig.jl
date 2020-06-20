
using Distributed, DataStructures

channels = 2
#display_fs = 2000
fs = 20000
# ratio = acquire_fs ÷ display_fs
refresh_hz = 50
# raw_buffer_samples = acquire_fs/refresh_hz

history_seconds = 8
history_samples = history_seconds * fs * channels

signal = CircularBuffer{Float64}(history_samples)
append!(signal, zeros(Float64, history_samples))
# time = collect((history_seconds * display_fs):-1:1) .* -1/display_fs

procs = 1
kmbslave = [("192.168.2.2",procs)]
const pid = addprocs(kmbslave)[1];

# Init NIDAQ on slave machine

if nprocs() > 1
    
    #nidaq_exp = Meta.parse("using NIDAQ, Distributed")
    #Distributed.remotecall_eval(Main, pid, nidaq_exp)
    wait(@spawnat pid @eval using NIDAQ, Distributed, ZeissCAN29)

    r_chan = RemoteChannel(() -> Channel{Vector{Float64}}(500), pid)    
    
    @spawnat pid @eval result = Float64[]
    @spawnat pid @eval dev = DefaultDev()
    wait(@spawnat pid @eval task = DAQTask{AI}())
    wait(@spawnat pid append!(task, dev.channels[AI][1], alias = "XII", tcfg = DAQmx.Diff, range = (-1.0,1.0)))
    wait(@spawnat pid append!(task, dev.channels[AI][3], alias = "Vm", tcfg = DAQmx.Diff, range = (-1.0,1.0)))

end


