module LabRig

include("pressure.jl")
using .PressureClamp

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

end # module
