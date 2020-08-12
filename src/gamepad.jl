
module Gamepad

import ..CImGui.GLFWBackend.GLFW: JOYSTICK_1, GetJoystickAxes, GetJoystickButtons

struct Axes
    x::Float32
    y::Float32
    trigger::Float32
    function Axes(axis_vec::Vector{Float32})
        offset::Float32 = axis_vec[3] + 1.0
        new(axis_vec[1], axis_vec[2], offset)
    end
end

struct Dpad
    up::Bool
    right::Bool
    down::Bool
    left::Bool
    function Dpad(dpad_vec::Vector{UInt8})
        new(dpad_vec...)
    end
end

struct Buttons
    A::Bool
    B::Bool
    X::Bool
    Y::Bool
    LB::Bool
    RB::Bool
    BACK::Bool
    START::Bool
    LOGI::Bool
    LHAT::Bool
    RHAT::Bool
    function Buttons(bvec::Vector{UInt8})
        new(bvec...)
    end
end

struct GamepadState
    button::Buttons
    DPAD::Dpad
    L::Axes
    R::Axes
    function GamepadState(axis_vals::Vector{Float32}, button_vals::Vector{UInt8})
        buttons = Buttons(button_vals[1:11])
        dpad = Dpad(button_vals[12:15])
        L = Axes(axis_vals[1:3])
        R = Axes(axis_vals[4:6])
        new(buttons, dpad, L, R)
    end
end

function poll(id = JOYSTICK_1)
    return GamepadState(GetJoystickAxes(id), GetJoystickButtons(id))
end

end

