
module ZeissRemote

using ..Distributed

const Z_VELOCITY = [50, 100, 250, 500, 1000, 4000] # zeiss focus speed ≈ 10x UMP speed

function init(pid)
    wait(@spawnat pid @eval using ZeissCAN29, Distributed)
end

function update_focus!(gamepad::GamepadState)::Int32
    LT, RT = gamepad.L.trigger, gamepad.R.trigger
    return LT > 0.4 ? (RT > 0.4 ? 0 : -Z_VELOCITY[speed_step]) :
                      (RT > 0.4 ? Z_VELOCITY[speed_step] : 0)
end

end # module
