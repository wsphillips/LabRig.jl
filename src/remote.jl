
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

num_worker_procs = 2
kmbslave = [("192.168.2.2",num_worker_procs)]

worker_pids = addprocs(kmbslave)

const nidaq_pid = worker_pids[1]
const zeiss_pid = worker_pids[2]

# Setup worker processes for Zeiss + NIDAQ

if nprocs() > 1
    
    wait(@spawnat nidaq_pid @eval using NIDAQ, Distributed)
    wait(@spawnat zeiss_pid @eval using ZeissCAN29, Distributed)
    
    # Init NIDAQ for continuous acquisition
    r_chan = RemoteChannel(() -> Channel{Vector{Float64}}(500), nidaq_pid)    
    @spawnat nidaq_pid @eval result = Float64[]
    @spawnat nidaq_pid @eval dev = DefaultDev()
    wait(@spawnat nidaq_pid @eval task = DAQTask{AI}())
    wait(@spawnat nidaq_pid append!(task, dev.channels[AI][2], alias = "XII", tcfg = DAQmx.Diff, range = (-1.0,1.0)))
    wait(@spawnat nidaq_pid append!(task, dev.channels[AI][3], alias = "Vm", tcfg = DAQmx.Diff, range = (-1.0,1.0)))

end


