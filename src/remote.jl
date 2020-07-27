
module Workers

using ..Distributed

num_worker_procs = 2
two_threads = "/home/wikphi/julia_2_threads.sh"
four_threads = "/home/wikphi/julia_4_threads.sh"

kmbslave = [("192.168.2.2",num_worker_procs)]

worker_pids = addprocs(kmbslave, exename=four_threads)

const nidaq_pid = worker_pids[1]
const zeiss_pid = worker_pids[2]


end # module

