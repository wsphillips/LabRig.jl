
module PressureClamp

using LabJack

export set_pressure

# LabJack digital/analog registers
const positive_cmd = "TDAC0"
const negative_cmd = "TDAC1"
const vac_supply = "EIO0"
const pressure_supply = "EIO2"
const vac_delivery = "EIO6"
const pressure_delivery = "EIO7"
const valves = "EIO_STATE" 
const perfusion_switch = "EIO1"

# We can't readout the state of TDAC, so we just keep track of whatever value we
# set it to ourselves.
CURRENT_PRESSURE = 0

function __init__()
    write_digital(perfusion_switch, 0)
    write_digital(vac_supply, 1)
    write_digital(pressure_supply, 0)
    write_digital(vac_delivery, 0)
    write_digital(pressure_delivery, 0)
    write_analog(positive_cmd, 0.0)
    write_analog(negative_cmd, 0.0)
end

function set_pressure(value)
    if value !== CURRENT_PRESSURE
        global CURRENT_PRESSURE = value
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
