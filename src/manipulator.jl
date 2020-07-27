module Manipulator

using LibUMP

const UMP_STEP = [250, 500, 1000, 2000, 4000, 8000]
const UMP_SPEED = [5, 10, 25, 50, 100, 400]

function __init__()
    UMP.set_refresh_time_limit(LibUMP.DEF_HANDLE, Cint(10))
    UMP.set_timeout(LibUMP.DEF_HANDLE, Cint(10))
    UMP.set_slow_speed_mode(LibUMP.DEF_HANDLE, Cint(1), Cint(1))
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

end # end
