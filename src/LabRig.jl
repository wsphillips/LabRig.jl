module LabRig


include("pressure.jl")
using .PressureClamp

using LibUMP

const UMP_STEP = [250, 500, 1000, 2000, 4000, 8000]
const UMP_SPEED = [5, 10, 25, 50, 100, 400]
const Z_VELOCITY = [50, 100, 250, 500, 1000, 4000] # zeiss focus speed ≈ 10x UMP speed
const SPEED_STEP_MAX = length(UMP_STEP)
UMP.set_refresh_time_limit(LibUMP.DEF_HANDLE, Cint(10))
UMP.set_timeout(LibUMP.DEF_HANDLE, Cint(10))
UMP.set_slow_speed_mode(LibUMP.DEF_HANDLE, Cint(1), Cint(1))

speed_step = 1

function inc_speed()
    speed_step == SPEED_STEP_MAX && return
    global speed_step += 1
end

function dec_speed()
    speed_step == 1 && return
    global speed_step -= 1
end
include("remote.jl")

function update_focus!(gamepad::GamepadState)::Int32
    LT, RT = gamepad.L.trigger, gamepad.R.trigger
    return LT > 0.4 ? (RT > 0.4 ? 0 : -Z_VELOCITY[speed_step]) : (RT > 0.4 ? Z_VELOCITY[speed_step] : 0)
end

function update_ump!(gamepad::GamepadState)
    X, Y = gamepad.R.x, gamepad.R.y
    LB, RB = gamepad.button.LB, gamepad.button.RB
    ystep = abs(Y) >= 0.4 ? flipsign(-UMP_STEP[speed_step], Y) : 0
    xstep = abs(X) >= 0.4 ? flipsign(-UMP_STEP[speed_step], X) : 0
    zstep = LB ? (RB ? 0 : -UMP_STEP[speed_step]) : (RB ? UMP_STEP[speed_step] : 0)
    if (xstep !== 0 || ystep !== 0 || zstep !== 0)
        move_3D_by(xstep, ystep, zstep, UMP_SPEED[speed_step])
    end
end

include("imgui_init.jl")
if nprocs() > 1
    wait(@spawnat nidaq_pid record!(result, task; remote = r_chan))
end

end # module
