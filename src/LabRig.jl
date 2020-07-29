module LabRig

using CImGui, DataStructures
using Distributed

include("gamepad.jl")
include("manipulator.jl")
include("pressure.jl")


#include("remote.jl")
#include("nidaq.jl")
#=
const SPEED_STEP_MAX = 6

speed_step = 1

function inc_speed()
    speed_step == SPEED_STEP_MAX && return
    global speed_step += 1
end

function dec_speed()
    speed_step == 1 && return
    global speed_step -= 1
end
=#
end # module
