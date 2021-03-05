
module GUI

using ..CImGui
using ..CImGui.CSyntax
using ..CImGui.CSyntax.CStatic
using ..CImGui.GLFWBackend
using ..CImGui.OpenGLBackend
using ..CImGui.GLFWBackend.GLFW
using ..CImGui.OpenGLBackend.ModernGL
using ..Gamepad, ..Zeiss, #=..Pressure,=# ..Manipulator, ..DAQ #..Camera
using ImPlot

import ThreadPools.@tspawnat
import CImGui: ImVec2, ImVec4, ImTextureID
import ..ZEISS_TID

# Globals
global IMGUI_WINDOW #TODO: as const ref
global IMGUI_CONTEXT #TODO: as const ref
const GLSL_VERSION = 130
const BACKGROUND_COLOR = Cfloat[0.45, 0.55, 0.60, 1.00]
const PRESSURE_TID = 2
const FRAME_STEP = Threads.Condition()
const SPEED_STEP_MAX = 6

mutable struct GlobalState
    SPEED_STEP::Int64
    USE_GAMEPAD::Ref{Bool}
    GAMEPAD::GamepadState
    GAMEPAD_CACHE::GamepadState
    function GlobalState()
        speedstep = 1
        usegamepad = Ref{Bool}(false)
        gamepad = Gamepad.poll()
        return new(speedstep, usegamepad, gamepad, gamepad)
    end
end

const g = Ref{GlobalState}()
# GLFW error callback
error_callback(err::GLFW.GLFWError) = @error "GLFW ERROR: code $(err.code) msg: $(err.description)"

function step_notify(c::Threads.Condition)
    lock(c)
    try
        notify(c)
    finally
        unlock(c)
    end
    return
end

function inc_speed()
    g[].SPEED_STEP == SPEED_STEP_MAX && return
    g[].SPEED_STEP += 1
end

function dec_speed()
    g[].SPEED_STEP == 1 && return
    g[].SPEED_STEP -= 1
end

function init_glfw()
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 4)
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 6)
    GLFW.SetErrorCallback(error_callback)
end

function setup()
    global IMGUI_CONTEXT = CImGui.CreateContext()
    CImGui.StyleColorsDark()
    fonts_dir = joinpath(@__DIR__, "..", "fonts")
    fonts = CImGui.GetIO().Fonts
    CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "MesloLGS.ttf"), 20)
    global IMGUI_WINDOW = GLFW.CreateWindow(1280, 720, "LabRig")
    @assert IMGUI_WINDOW != C_NULL
    GLFW.MakeContextCurrent(IMGUI_WINDOW)
    GLFW.SwapInterval(1)  # enable vsync; 0 for disabled, 2 for 30fps, 3 for 20fps, etc
    ImGui_ImplGlfw_InitForOpenGL(IMGUI_WINDOW, true)
    ImGui_ImplOpenGL3_Init(GLSL_VERSION)
end

function new_frame!()
    ImGui_ImplOpenGL3_NewFrame()
    ImGui_ImplGlfw_NewFrame()
    CImGui.NewFrame()
end

function render!(window = IMGUI_WINDOW, clear_color = BACKGROUND_COLOR)
    CImGui.Render()
    GLFW.MakeContextCurrent(window)
    display_w, display_h = GLFW.GetFramebufferSize(window)
    glViewport(0, 0, display_w, display_h)
    glClearColor(clear_color...)
    glClear(GL_COLOR_BUFFER_BIT)
    ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())
    GLFW.MakeContextCurrent(window)
    GLFW.SwapBuffers(window)
end

function shutdown!(; window = IMGUI_WINDOW, ctx = IMGUI_CONTEXT)
    ImGui_ImplOpenGL3_Shutdown()
    ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(ctx)
    GLFW.DestroyWindow(window)
end
#=
# do this later...
function menubar()
    if CImGui.BeginMainMenuBar()
        if CImGui.BeginMenu("File")
=#

abstract type UIElement end
#=
mutable struct CameraUI <: UIElement
    frame::Vector{UInt16}
    pipeline::ImagePipeline
    pipeline_job::Task
    texID::UInt32
    livemode::Bool
    function CameraUI()
        livemode = false
        frame = zeros(UInt16, 1200*1200)
        pipeline = ImagePipeline(frame)
        pipeline_job = @async 0
        texID = Camera.gen_textures(1)[1]
        Camera.load_texture(texID, frame, 1200, 1200)
        camui = new(frame, pipeline, pipeline_job, texID, livemode)
        finalizer(camui) do camui
            camui.livemode && Camera.stopcont()
        end
        return camui
    end
end

function (c::CameraUI)()
    CImGui.Begin("Live View")
    if CImGui.Button("Start Live")
        try
            Camera.polled_cont!()
            c.pipeline_job = @async sleep(1.0)
            c.livemode = true
        catch e
            @warn "Failed to initialize live mode"
            c.livemode = false
        end
    end
    CImGui.SameLine()
    if CImGui.Button("Stop Live")
        Camera.stop_cont()
        c.livemode = false
    end
    if c.livemode
        Camera.reload_texture(c.texID, c.pipeline.out, 1200, 1200)
        CImGui.Image(ImTextureID(Int(c.texID)), ImVec2(1200,1200), ImVec2(0,0), ImVec2(1,1),
                     ImVec4(1.0,1.0,1.0,1.0), ImVec4(1,1,1,1))
        if istaskdone(c.pipeline_job)
            try
                c.frame .= Camera.latest_frame()
                c.pipeline_job = @tspawnat 6 c.pipeline(c.frame)
            catch e
                @warn "Frame dropped"
            end
        end
    end
    CImGui.End()
end
=#

#=
mutable struct PressureUI <: UIElement
    cmd_pressure::Ref{Cint}
    show_history::Bool
    fs::Int64
    coax_amp::Ref{Int32}
    coax_duration::Ref{Float32}
    coax_repeat::Ref{Int32}
    rupture_amp::Ref{Int32}
    rupture_duration::Ref{Float32}
    rupture_repeat::Ref{Int32}
    function PressureUI()
        cmd_pressure = Ref{Cint}(0) 
        @tspawnat PRESSURE_TID Pressure.stream_out(FRAME_STEP)
        new(cmd_pressure, false, 60, Ref{Int32}(5), Ref{Float32}(3.0), Ref{Int32}(3), Ref{Int32}(-30), Ref{Float32}(1.0), Ref{Int32}(3))
    end
end

function (p::PressureUI)()
    CImGui.Begin("Pressure control.")
    CImGui.Button("Perfusion Channel: " * (PRIMARY_SOLUTION[] ? "Main" : "Drug")) && toggle_solution()
    CImGui.Text("Current Presure: $(Pressure.CURRENT_PRESSURE[])")
    CImGui.DragInt("kPa", p.cmd_pressure, 0.5, -20, 100)
    CImGui.Button("On Cell!") && (p.cmd_pressure[] = Cint(-1))
    CImGui.SameLine()
    CImGui.Button("NEUTRAL") && (p.cmd_pressure[] = Cint(0))
    CImGui.SameLine()
    CImGui.Button("Near cell") && (p.cmd_pressure[] = Cint(1))
    CImGui.SameLine()
    CImGui.Button("Bath mode") && (p.cmd_pressure[] = Cint(20))

    #build an interface for sending ramps/transitions
    CImGui.InputInt("Coax Amp", p.coax_amp)
    CImGui.InputFloat("Coax Duration", p.coax_duration)
    CImGui.InputInt("Coax repeat", p.coax_repeat)
    CImGui.Button("Coax Cell") && Pressure.coaxcell(p.coax_amp[], p.fs, p.coax_duration[], p.coax_repeat[])
    
    CImGui.InputInt("Rupture Amp", p.rupture_amp)
    CImGui.InputFloat("Rupture Duration", p.rupture_duration)
    CImGui.InputInt("Rupture repeat", p.rupture_repeat)
    CImGui.Button("Rupture cell") && Pressure.attempt_break(p.rupture_amp[], p.fs, p.rupture_duration[], p.rupture_repeat[])
    
    
    if isempty(Pressure.STREAM_CHANNEL)
        put!(Pressure.STREAM_CHANNEL, [p.cmd_pressure[]])
    end
    CImGui.Button("Toggle History") && (p.show_history = !p.show_history)
    if p.show_history
        if ImPlot.BeginPlot("Pressure Sensor", "", "", ImVec2(-1, 300))
            ImPlot.PlotLine(collect(Pressure.PROBE_HISTORY), label = "kPa")
            ImPlot.EndPlot()
        end
    end
    CImGui.End()
end
=#
mutable struct FocusUI <: UIElement
    home_pos::Int64
    work_pos::Int64
    function FocusUI()
        new(0,0)
    end
end

function follow_work(focus_zpos, fui::FocusUI)
    ump_position = Manipulator.get_position()
    diff = Cint(fui.work_pos - focus_zpos)
    target_position = Manipulator.Position(ump_position.x, ump_position.y, ump_position.z + diff, nothing)
    Manipulator.moveto(target_position)
end

function follow_home(focus_zpos, fui::FocusUI)
    ump_position = Manipulator.get_position()
    diff = Cint(fui.home_pos - focus_zpos)
    target_position = Manipulator.Position(ump_position.x, ump_position.y, ump_position.z + diff, nothing)
    Manipulator.moveto(target_position)
end

function (f::FocusUI)()
    position, velocity = fetch(@tspawnat ZEISS_TID Zeiss.get_zeiss_state())
    gamepad = g[].GAMEPAD
    gamepad_cache = g[].GAMEPAD_CACHE 
    CImGui.Begin("Focus control")
    CImGui.Checkbox("Use gamepad", g[].USE_GAMEPAD) 
    CImGui.Text("Position: $position")
    CImGui.Button("Go Home") && Zeiss.moveto(f.home_pos)
    CImGui.SameLine()
    CImGui.Button("Set Home: $(f.home_pos)") && (f.home_pos = position)
    CImGui.Button("Go Work") && Zeiss.moveto(f.work_pos)
    CImGui.SameLine()
    CImGui.Button("Set Work: $(f.work_pos)") && (f.work_pos = position)
    CImGui.Button("Follow Work") && follow_work(position, f)
    # Follow home is disabled atm. You would need to do it by caching Z-axis positions. The current logic fails
    # because you need to move the focus first (which alters its position) and changes the calculated offset. 
    # and providing a done event that won't cause frame lag (e.g. wait for move to finish for X frames; track progress by incrementing a counter on each frame after a move)
    # In general, a return to a position where the manipulator can be retracted for pipette change would be more useful than return to home focus position!!
    # CImGui.SameLine()
    # CImGui.Button("Follow Home") && follow_home(position, f)
    CImGui.Button("STOPPP!!!!!") && Zeiss.stop!()
    if g[].USE_GAMEPAD[] # need global state for gamepad
        CImGui.Text("Z Axis Velocity: $velocity")
        CImGui.Text("Speed step: $(g[].SPEED_STEP)")
        gamepad.DPAD.left && !gamepad_cache.DPAD.left && dec_speed()
        gamepad.DPAD.right && !gamepad_cache.DPAD.right && inc_speed()
        gamepad.button.B ? Zeiss.stop!() : new_velocity = Zeiss.update_velocity(gamepad, g[].SPEED_STEP)
        Zeiss.set_velocity(new_velocity)
        Manipulator.step!(gamepad)
    end
    CImGui.End()
end

mutable struct DAQUI <: UIElement
    recording::DAQ.Recording
    data::Vector{Float64}
    xii_indexes::StepRange
    vm_indexes::StepRange
    record::Bool
    function DAQUI()
        recording = DAQ.Recording()
        xii_indexes = 1:4:length(recording.signal)
        vm_indexes = 2:4:length(recording.signal)
        data = zeros(length(recording.signal))
        return new(recording, data, xii_indexes, vm_indexes, false)
    end
end

function (d::DAQUI)()
    CImGui.Begin("Ephys Data")
    if !d.record
        if CImGui.Button("Start acquisition.")
            wait(d.recording())
            d.record = true
        end
    else
        if CImGui.Button("Stop acquisition.")
            DAQ.stop(d.recording.task)
            d.record = false
        else
            d.data .= collect(d.recording.signal)
            
            if ImPlot.BeginPlot("Vm Data", "","", ImVec2(-1,700))
                # downsampling to 2kHz display
                ImPlot.PlotLine(d.data[d.vm_indexes], label = "Vm")
                ImPlot.EndPlot()
            end
            
            if ImPlot.BeginPlot("XII Data", "", "", ImVec2(-1,500))
                #downsampling to 2kHz display
                ImPlot.PlotLine(d.data[d.xii_indexes], label = "XII")
                ImPlot.EndPlot()
            end
        end
    end
    CImGui.End()
end

mutable struct StimUI <: UIElement
    stim::DAQ.Stimulus
    user_interval::Ref{Float32}
    user_duration::Ref{Float32}
    function StimUI()
        stim = DAQ.Stimulus()
        return new(stim, Ref{Float32}(0.05), Ref{Float32}(0.03))
    end
end

function (s::StimUI)()
    CImGui.Begin("Stimulus Panel")
    
    CImGui.Button("Patch pulses.") && DAQ.pulsetiming!(s.stim, 0.05, 0.03)
    CImGui.SameLine()
    CImGui.Button("Ia/Ih pulses.") && DAQ.pulsetiming!(s.stim, 1.0, 0.4)
    CImGui.SameLine()
    CImGui.Button("Custom pulses.") && DAQ.pulsetiming!(s.stim, Float64(s.user_interval[]), Float64(s.user_duration[]))
    CImGui.SameLine()
    CImGui.Button("Stop pulses.") && DAQ.stop(s.stim)

    CImGui.InputFloat("Custom interval", s.user_interval)
    CImGui.InputFloat("Custom duration", s.user_duration)

    CImGui.End()
end

mutable struct ElementState
    show::Bool
    hotload::Bool
    function ElementState()
        return new(false, false)
    end
end

function build_ui()
    ui = IdDict{UIElement, ElementState}()
    for x in subtypes(UIElement)
        ui[x()] = ElementState()
    end
    return ui
end

function run_loop(; window = IMGUI_WINDOW)

    @async try
        g[] = GlobalState()
        ui = UIElement[]
        for x in [FocusUI, #=PressureUI,=# DAQUI, StimUI] #FIXME: add CameraUI back after adjusting hist
            push!(ui, x())
        end
        while !GLFW.WindowShouldClose(window)
            GLFW.PollEvents()
            new_frame!()                
            g[].GAMEPAD = Gamepad.poll()
            
            # run UI functions...
            for el in ui
                Base.invokelatest(el)
            end
            # cache gamepad state
            g[].GAMEPAD_CACHE = g[].GAMEPAD
            # trigger pipelines on other threads
            step_notify(FRAME_STEP)
            render!()
            yield()
        end # main loop
    catch e
        @error "Error in renderloop!" exception=e
        Base.show_backtrace(stderr, catch_backtrace())
    finally
        shutdown!()
    end # try-catch-finally; @async; GC.@preserve
end # function

function launch!()
    setup()
    run_loop()
end

end # module
