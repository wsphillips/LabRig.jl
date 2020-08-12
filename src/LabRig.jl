module LabRig

using CImGui, DataStructures
using CImGui.CSyntax
using CImGui.CSyntax.CStatic
using DataStructures
import ThreadPools.@tspawnat
const ZEISS_TID = 3
const PIPELINE_THREADS = 4:8

include("gamepad.jl")
include("manipulator.jl")
include("pressure.jl")
include("zeiss.jl")
include("daq.jl")
include("camera.jl")
include("gui.jl")

export Gamepad, Manipulator, Pressure, GUI, CImGui, CSyntax, CStatic, Zeiss, DAQ, Camera


function init_subsystems()
    Pressure.initialize()
    @tspawnat ZEISS_TID Zeiss.server_init()
end

end # module
