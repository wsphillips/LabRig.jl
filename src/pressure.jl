module Pressure

using LabJack

# LabJack digital/analog registers
const positive_cmd = "TDAC0"
const negative_cmd = "TDAC1"
const vac_supply = "EIO0"
const pressure_supply = "EIO2"
const vac_delivery = "EIO6"
const pressure_delivery = "EIO7"
const valves = "EIO_STATE" 
const perfusion_switch = "EIO1"

# We can't readout the values of TDAC, so we cache state instead
const CURRENT_PRESSURE = Threads.Atomic{Int32}(0)
const STREAM_CHANNEL = Channel{Vector{Int32}}(250)
const RUN_STREAM = Threads.Atomic{Bool}(true)

atexit() do
    RUN_STREAM[] = false
    isopen(STREAM_CHANNEL) && close(STREAM_CHANNEL)
end

function get_pressure()
    return CURRENT_PRESSURE[]
end

function init_levels()
    # initialize to safe values
    write_digital(perfusion_switch, 0)
    write_digital(vac_supply, 1)
    write_digital(pressure_supply, 0)
    write_digital(vac_delivery, 0)
    write_digital(pressure_delivery, 0)
    write_analog(positive_cmd, 0.0)
    write_analog(negative_cmd, 0.0)
end

function initialize()
    LabJack.init_default()
    init_levels()
end

function stream_out(cycle_lock::Threads.Condition)
    @async while RUN_STREAM[]
        pressures = take!(STREAM_CHANNEL)
        for val in pressures
            lock(cycle_lock)
            try
                wait(cycle_lock)
                set(val)
                GC.safepoint()
            finally
                unlock(cycle_lock)
            end
        end
    end
end

function set(value)
    if value !== CURRENT_PRESSURE[]
        Threads.atomic_xchg!(CURRENT_PRESSURE, value)
        if value == 0
            write_analog(positive_cmd, 0.0)
            write_analog(negative_cmd, 0.0)
            read_digital(valves)[7] == 1 && write_digital(vac_delivery, 0)
            read_digital(valves)[8] == 1 && write_digital(pressure_delivery, 0)
        elseif value > 0
            read_digital(valves)[7] !== 0 && write_digital(vac_delivery, 0)
            read_digital(valves)[8] !== 1 && write_digital(pressure_delivery, 1)
            write_analog(positive_cmd, value/10)
        elseif value < 0
            read_digital(valves)[7] !== 1 && write_digital(vac_delivery, 1)
            read_digital(valves)[8] !== 0 && write_digital(pressure_delivery, 0)
            write_analog(negative_cmd, value/-5)
        end
    end
end

end
