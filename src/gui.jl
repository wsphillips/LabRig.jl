
module GUI

using ..CImGui
using ..CImGui.CSyntax
using ..CImGui.CSyntax.CStatic
using ..CImGui.GLFWBackend
using ..CImGui.OpenGLBackend
using ..CImGui.GLFWBackend.GLFW
using ..CImGui.OpenGLBackend.ModernGL
using ..Gamepad, ..Zeiss, ..Pressure, ..Manipulator, ..DAQ, ..Camera
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
const SPEED_STEP = Ref{Int64}(1)

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
    SPEED_STEP[] == SPEED_STEP_MAX && return
    SPEED_STEP[] += 1
end

function dec_speed()
    SPEED_STEP[] == 1 && return
    SPEED_STEP[] -= 1
end

function init_glfw()
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 0)
    GLFW.SetErrorCallback(error_callback)
end

function setup()
    global IMGUI_CONTEXT = CImGui.CreateContext()
    CImGui.StyleColorsDark()
    global IMGUI_WINDOW = GLFW.CreateWindow(1280, 720, "LabRig")
    @assert IMGUI_WINDOW != C_NULL
    GLFW.MakeContextCurrent(IMGUI_WINDOW)
    GLFW.SwapInterval(1)  # enable vsync; 0 for disabled
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
#TODO: The camera fails to return the latest frame if we call too quickly
# e.g. before the first frame has been acquired. We should therefore have a pause
# between initializing circular buffer acquisition and the first call to `latest_frame()`
function run_loop(; window = IMGUI_WINDOW)
    @async begin
        try
            @tspawnat PRESSURE_TID Pressure.stream_out(FRAME_STEP)
            use_gamepad = false
            gamepad_cache = Gamepad.poll()
            Z_HOME = 0
            Z_WORK = 0
            tex_id = Camera.gen_textures(1)[1]
            frame = Camera.PVCAM.initialize_cont()
            Camera.load_texture(tex_id, frame, 1200, 1200)
            daq_recording = DAQ.Recording()
            data = zeros(length(daq_recording.signal))
            daq_recording()
            while !GLFW.WindowShouldClose(window)
                GLFW.PollEvents()
                new_frame!()                
                gamepad = Gamepad.poll()
                
                # Camera live view
                CImGui.Begin("Live View")
                # maybe we should wrap this in a try-catch to not crash on dropped frame queries?
                frame .= Camera.latest_frame()
                Camera.reload_texture(tex_id, frame, 1200, 1200)
                CImGui.Image(ImTextureID(Int(tex_id)), ImVec2(1200,1200), ImVec2(0,0), ImVec2(1,1),
                             ImVec4(1.0,1.0,1.0,1.0), ImVec4(1,1,1,1))
                CImGui.End()

                # Pressure control 
                @cstatic f=Cint(0) begin
                    CImGui.Begin("Pressure control.")
                    @c CImGui.DragInt("kPa", &f, 0.5, -20, 100)
                    CImGui.Button("On Cell!") && (f = Cint(-1))
                    CImGui.Button("NEUTRAL") && (f = Cint(0))
                    CImGui.Button("Bath mode") && (f = Cint(20))
                    #build an interface for sending ramps/transitions
                    put!(Pressure.STREAM_CHANNEL, [f])
                    CImGui.End()
                end
                # Focus control
                CImGui.Begin("Focus control")
                position, velocity = fetch(@tspawnat ZEISS_TID Zeiss.get_zeiss_state())
                @c CImGui.Checkbox("Use gamepad", &use_gamepad) 
                CImGui.Text("Position: $position")
                CImGui.Button("Set Home: $Z_HOME") && (Z_HOME = position)
                CImGui.Button("Set Work: $Z_WORK") && (Z_WORK = position)
                CImGui.Button("Go Home") && Zeiss.moveto(Z_HOME)
                CImGui.Button("Go Work") && Zeiss.moveto(Z_WORK)
                CImGui.Button("STOPPP!!!!!") && Zeiss.stop!()
                if use_gamepad
                    CImGui.Text("Z Axis Velocity: $velocity")
                    CImGui.Text("Speed step: $(SPEED_STEP[])")
                    gamepad.DPAD.left && !gamepad_cache.DPAD.left && dec_speed()
                    gamepad.DPAD.right && !gamepad_cache.DPAD.right && inc_speed()
                    gamepad.button.B ? Zeiss.stop!() : new_velocity = Zeiss.update_velocity(gamepad, SPEED_STEP[])
                    Zeiss.set_velocity(new_velocity)
                    Manipulator.step!(gamepad)
                end
                CImGui.End()
                # NIDAQ data plotting
                data .= fetch(@tspawnat DAQ.NIDAQ_TID[] collect(daq_recording.signal))
                CImGui.Begin("Vm Data")
                if ImPlot.BeginPlot("Vm Data", "","", ImVec2(-1,700))
                    # downsampling to 2kHz display
                    ImPlot.PlotLine(1:20:length(data), data, label = "Vm")
                    ImPlot.EndPlot()
                end
                CImGui.End()
                CImGui.Begin("XII Data")
                if ImPlot.BeginPlot("XII Data", "", "", ImVec2(-1,400))
                    #downsampling to 1kHz display
                    ImPlot.PlotLine(2:40:length(data), data, label = "XII")
                    ImPlot.EndPlot()
                end
                CImGui.End()
                # cache gamepad state
                gamepad_cache = gamepad
                # trigger pipelines on other threads
                step_notify(FRAME_STEP)
                render!()
            end # main loop
        catch e
            @error "Error in renderloop!" exception=e
            Base.show_backtrace(stderr, catch_backtrace())
        finally
            shutdown!()
            @tsapwnat DAQ.NIDAQ_TID[] DAQ.stop(daq_recording.task)
            Camera.stop_cont()
        end # try-catch-finally
    end # async block
end # function

function launch!()
    setup()
    run_loop()
end

end # module
