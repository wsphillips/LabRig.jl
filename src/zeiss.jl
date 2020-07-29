
module ZeissRemote

using ..Distributed
import ..Gamepad.GamepadState
export ZeissState, update_focus!

global ZEISS_PID
const COMMANDS = Channel(100)
const STATE = Channel()
const Z_VELOCITY = [50, 100, 250, 500, 1000, 4000] # zeiss focus speed ≈ 10x UMP speed

struct ZeissState
    position::Integer
    velocity::Integer
    moving::Bool
    step_in_progress::Bool 
end

function init(pid)
    if !@isdefined ZEISS_PID
        global ZEISS_PID =pid
    end
    wait(@spawnat pid @eval using ZeissCAN29, Distributed)
    # start command/state channel worker
end

function update_focus!(gamepad::GamepadState, speed_step)::Int32
    LT, RT = gamepad.L.trigger, gamepad.R.trigger
    return LT > 0.4 ? (RT > 0.4 ? 0 : -Z_VELOCITY[speed_step]) :
                      (RT > 0.4 ? Z_VELOCITY[speed_step] : 0)
end

# wrapper functions for RPCs

function set_z_position!(pos::Integer)
    @spawnat ZEISS_PID moveto(pos)
end

function velocity(new_velocity::Integer)
    @spawnat ZEISS_PID set_velocity(new_velocity)
end

function get_position()
    @spawnat ZEISS_PID pollposition!()
end

function stop_zaxis()
    @spawnat ZEISS_PID stop!()
end

function fetch_state()
    vals = fetch(@spawnat ZEISS_PID get_zeiss_state())
    return ZeissState(vals...)
end

function command_reducer()
    cmd_queue = []
    while isready(COMMANDS)
        push!(cmd_queue, take!(COMMANDS))
    end
    current = fetch_state() # retrieve state in all cases
    if length(cmd_queue > 0)
        cmds = getindex.(cmd_queue, 1)
        args = getindex.(cmd_queue, 2)
        # Reducer logic
        if stop_zaxis ∈ cmds
            stop_zaxis() # explicit stop is an emergency; send always + dump other commands
        else
            for (i, v) in enumerate(cmds)
                v == get_position && getposition()
                if v == set_z_position
                    current.moving && stop_zaxis()
                    set_z_position(args[i])
                    break
                elseif v == velocity && !current.step_in_progress # we ignore the controller when making a set position move
                    args[i] !== current.velocity && velocity(args[i]) # modify if we aren't at the correct velocity
                end
            end
        end
    end
    
    put!(STATE, current) # dropoff the state for the gui loop to pickup

    return
end # module
