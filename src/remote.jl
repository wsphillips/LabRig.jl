
#module Workers
using Distributed

num_worker_procs = 2
kmb2 = [("192.168.2.2",num_worker_procs)]
worker_pids = addprocs(kmb2)
const NIDAQ_PID = worker_pids[1]
const ZEISS_PID = worker_pids[2]

#end # module

