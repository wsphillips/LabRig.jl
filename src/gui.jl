
module GUI

using CImGui
using CImGui.CSyntax
using CImGui.CSyntax.CStatic
using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using CImGui.GLFWBackend.GLFW
using CImGui.OpenGLBackend.ModernGL
using Printf
using CImPlot

using ..Gamepad

global IMGUI_WINDOW
global IMGUI_CONTEXT
const GLSL_VERSION = 130
const BACKGROUND_COLOR = Cfloat[0.45, 0.55, 0.60, 1.00]

# setup GLFW error callback
error_callback(err::GLFW.GLFWError) = @error "GLFW ERROR: code $(err.code) msg: $(err.description)"

function __init__()
    # These should only need to be set once
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 0)
    GLFW.SetErrorCallback(error_callback)
end

function setup_gui()
    # setup ImGui context
    global IMGUI_CONTEXT = CImGui.CreateContext()
    # set ImGui style
    CImGui.StyleColorsDark()

    # load Fonts
    fonts_dir = joinpath(@__DIR__, "..", "fonts")
    fonts = CImGui.GetIO().Fonts
    CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Roboto-Medium.ttf"), 16)

    # create window
    global IMGUI_WINDOW = GLFW.CreateWindow(1280, 720, "LabRig")
    @assert IMGUI_WINDOW != C_NULL
    GLFW.MakeContextCurrent(IMGUI_WINDOW)
    GLFW.SwapInterval(1)  # enable vsync

    # setup Platform/Renderer bindings
    ImGui_ImplGlfw_InitForOpenGL(IMGUI_WINDOW, true)
    ImGui_ImplOpenGL3_Init(GLSL_VERSION)
end

function new_frame!()
    ImGui_ImplOpenGL3_NewFrame()
    ImGui_ImplGlfw_NewFrame()
    CImGui.NewFrame()
end

function render!(window = IMGUI_WINDOW, clear_color = BACKGROUND_COLOR)
    # tell imgui to generate draw data
    CImGui.Render()
    
    # get the current window size from GLFW, resize the OpenGL viewport and fill
    # it with the clear color (background color)
    GLFW.MakeContextCurrent(window)
    display_w, display_h = GLFW.GetFramebufferSize(window)
    glViewport(0, 0, display_w, display_h)
    glClearColor(clear_color...)
    glClear(GL_COLOR_BUFFER_BIT)
    
    # fetch and render the draw data with OpenGL backend
    ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())

    # swap to newly rendered buffer
    GLFW.MakeContextCurrent(window)
    GLFW.SwapBuffers(window)
end


function shutdown!(; window = IMGUI_WINDOW, ctx = IMGUI_CONTEXT)
    ImGui_ImplOpenGL3_Shutdown()
    ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(ctx)
    GLFW.DestroyWindow(window)
end

function run_main_loop(; window = IMGUI_WINDOW)
    @async begin
        # Main program loop
        try
            use_gamepad = false
            gamepad_cache = poll_gamepad()
        
            while !GLFW.WindowShouldClose(window)
                GLFW.PollEvents()
                # start the Dear ImGui frame
                new_frame!()                

                # NIDAQ data retrieval
                data = take!(r_chan)
                append!(signal, data)
                xii_sig = Float32.(signal[1:20:end])
                vm_sig = Float32.(signal[2:20:end])
                
                # Gamepad state update
                gamepad = poll_gamepad()
               
                # GUI Windows

                # Pressure control 

                @cstatic f=Cint(0) begin
                    set_pressure(f)
                    CImGui.Begin("Pressure control.")
                    CImGui.Text("Pressure control")  # display some text
                    @c CImGui.DragInt("kPa", &f, 0.5, -20, 100)  # edit 1 float using a slider from 0 to 1
                    
                    if (CImGui.Button("On Cell!"))
                        f = Cint(-1)
                    end
        
                    if (CImGui.Button("NEUTRAL"))
                        f = Cint(0)
                    end
        
                    if (CImGui.Button("Bath mode"))
                        f = Cint(20)
                    end
        
                    CImGui.End()
                end
        
                @cstatic position=Cint(0) home=Cint(0) work=Cint(0) velocity=Cint(0) moving = false begin
                    (position, velocity, moving) = fetch(@spawnat zeiss_pid get_zeiss_state())
                    CImGui.Begin("Focus control")

                    @c CImGui.Checkbox("Use gamepad", &use_gamepad) 

                    CImGui.Button("Position: $position") && ZeissRemote.get_position()
                    CImGui.Button("Set Home: $home") && (home = position)
                    CImGui.Button("Set Work: $work") && (work = position)
                    CImGui.Button("Go Home") && ZeissRemote.zposition!(home)
                    CImGui.Button("Go Work") && ZeissRemote.zposition!(work)
                    
                    if !use_gamepad
                    @c CImGui.DragInt("Axis Velocity", &velocity, 1.0, -2000, 2000)
                    else
                        CImGui.Text("Z Axis Velocity: $velocity")
                        CImGui.Text("Speed step: $speed_step")
                        if gamepad.DPAD.left && !gamepad_cache.DPAD.left
                            dec_speed()
                        end
                        if gamepad.DPAD.right && !gamepad_cache.DPAD.right
                            inc_speed()
                        end
                        update_ump!(gamepad)
                        if gamepad.button.B
                            @spawnat zeiss_pid stop!()
                        else
                            new_velocity = update_focus!(gamepad)
                        end
                        @spawnat zeiss_pid set_velocity(Int32(new_velocity*100))
                    end
                    
                    if (CImGui.Button("STOPPP!!!!!"))
                        @spawnat zeiss_pid stop!()
                    end
        
                    CImGui.End()
                end
                
                # NIDAQ data plotting

                CImGui.Begin("Vm Data")
                if (CImPlot.BeginPlot("Vm Data", "","", CImGui.ImVec2(-1,700),
                                      CImPlot.LibCImPlot.ImPlotFlags_Default,
                                      CImPlot.LibCImPlot.ImPlotAxisFlags_Default,
                                      CImPlot.LibCImPlot.ImPlotAxisFlags_Default))

                    CImPlot.Plot(vm_sig, offset = 0, stride = 1, label = "Vm")

                    CImPlot.EndPlot()
                end
                CImGui.End()
               
                CImGui.Begin("XII Data")
                if (CImPlot.BeginPlot("XII Data", "", "", CImGui.ImVec2(-1,400),
                                      CImPlot.LibCImPlot.ImPlotFlags_Default,
                                      CImPlot.LibCImPlot.ImPlotAxisFlags_Default,
                                      CImPlot.LibCImPlot.ImPlotAxisFlags_Default))

                    CImPlot.Plot(xii_sig, offset = 0, stride = 1, label = "XII")

                    CImPlot.EndPlot()
                end
                CImGui.End()
                
                # cache gamepad state
                gamepad_cache = gamepad
            
                render!()

            end # main loop

        catch e
            @error "Error in renderloop!" exception=e
            Base.show_backtrace(stderr, catch_backtrace())
        finally
            shutdown!()
            @spawnat nidaq_pid stop(task)
        end # try-catch-finally

    end # async block

end # function

function launch_gui()
    setup_gui()
    run_main_loop()
end

end # module
