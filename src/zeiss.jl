
module Zeiss

using ZeissCAN29
import ..Gamepad.GamepadState
export update_velocity

const V_SCALE = Int32(100)
const VELOCITY = Int32[50, 100, 250, 500, 1000, 4000] .* V_SCALE # zeiss focus speed ≈ 10x UMP speed

function update_velocity(gamepad::GamepadState, speed_step::Integer)::Int32
    LT, RT = gamepad.L.trigger, gamepad.R.trigger
    return LT > 0.4 ? (RT > 0.4 ? 0 : -VELOCITY[speed_step]) :
                      (RT > 0.4 ? VELOCITY[speed_step] : 0)
end

end # module
