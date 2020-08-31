module Pressure

using LabJack
using DataStructures

# LabJack digital/analog registers
const positive_cmd = "TDAC0"
const negative_cmd = "TDAC1"
const vac_supply = "EIO0"
const pressure_supply = "EIO2"
const vac_delivery = "EIO6"
const pressure_delivery = "EIO7"
const valves = "EIO_STATE" 
const perfusion_switch = "EIO1"
const vac_sensor = "AIN2"
const probe_sensor = "AIN3"

# We can't readout the values of TDAC, so we cache state instead
const CURRENT_PRESSURE = Threads.Atomic{Float32}(0)
const STREAM_CHANNEL = Channel{Vector{Float32}}(250)
const RUN_STREAM = Threads.Atomic{Bool}(true)
const MONITOR = Threads.Atomic{Bool}(true)
const PROBE_HISTORY = CircularBuffer{Float32}(500)

atexit() do
    RUN_STREAM[] = false
    MONITOR[] = false
    isopen(STREAM_CHANNEL) && close(STREAM_CHANNEL)
end

function coaxcell(amplitude, fs, seconds_per_cycle, repetitions)
    a = range(-π/2, 3π/2, length = round(Int, fs * seconds_per_cycle))
    wave = Float32.(repeat(sin.(a) .* amplitude, outer=repetitions))
    put!(STREAM_CHANNEL, wave)
end

function attempt_break(amplitude, fs, seconds_per_cycle, repetitions)
    lag = fill(Float32(-1.0), 30)
    a = collect(Float32, range(-1, amplitude, length = round(Int, fs * seconds_per_cycle)))
    a = vcat(lag, a, lag)
    wave = repeat(a, outer=repetitions)
    put!(STREAM_CHANNEL, wave)
end

function get_pressure()
    return CURRENT_PRESSURE[]
end

function init_levels()
    # initialize to safe values
    write_digital(perfusion_switch, 0)
    write_digital(pressure_supply, 0)
    write_digital(vac_delivery, 0)
    write_digital(pressure_delivery, 0)
    write_analog(positive_cmd, 0.0)
    write_analog(negative_cmd, 0.0)
end

function pressure_transduce(volts)::Float32
    return (volts - 3.0479)*50.0
end

function vac_supply_transduce(volts)::Float32
    return (1 - (volts - 1) / 4) * -101
end

function vac_monitor()
    @async while MONITOR[]
        v = read_analog(vac_sensor)
        p = vac_supply_transduce(v)
        if p >= -60
            write_digital(vac_supply, 1)
            sleep(5.0)
            write_digital(vac_supply, 0)
        else
            yield()
            sleep(30.0)
        end
        GC.safepoint()
    end
end

function probe_monitor()
    @async while MONITOR[]
        v = read_analog(probe_sensor)
        p = pressure_transduce(v)
        push!(PROBE_HISTORY, p)
        GC.safepoint()
        yield()
        sleep(0.02)
    end
end

function initialize()
    LabJack.init_default()
    init_levels()
    vac_monitor()
    fill!(PROBE_HISTORY, Float32(0.0))
    probe_monitor()
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
            write_analog(positive_cmd, 0.1)
            write_analog(negative_cmd, 0.1)
            write_digital(vac_delivery, 1)
            write_digital(pressure_delivery, 1)
        elseif value > 0
            write_digital(vac_delivery, 0)
            write_digital(pressure_delivery, 1)
            write_analog(positive_cmd, value/10)
        elseif value < 0
            write_digital(vac_delivery, 1)
            write_digital(pressure_delivery, 0)
            write_analog(negative_cmd, value/-5)
        end
    end
end

end
