module LabRig


include("pressure.jl")
using .PressureClamp

using CImGui
using CImGui.CSyntax
using CImGui.CSyntax.CStatic
using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using CImGui.GLFWBackend.GLFW
using CImGui.OpenGLBackend.ModernGL
using Printf
using CImPlot

include("remote.jl")

include("imgui_init.jl")
if nprocs() > 1
    wait(@spawnat pid record!(result, task; remote = r_chan))
end

# Main program loop
const ps1 = GLFW.JOYSTICK_1
try
    clear_color = Cfloat[0.45, 0.55, 0.60, 1.00]
    use_controller = false
    t = Float32.(collect(1:fld(length(signal),2)))
    t = repeat(t, inner=2)

    while !GLFW.WindowShouldClose(window)
        GLFW.PollEvents()
        # start the Dear ImGui frame
        ImGui_ImplOpenGL3_NewFrame()
        ImGui_ImplGlfw_NewFrame()
        CImGui.NewFrame()
        
        data = take!(r_chan)
        append!(signal, data)
        v_sig = Float32.(signal)

        @cstatic f=Cint(0) begin
            set_pressure(f)
            CImGui.Begin("Pressure control.")
            CImGui.Text("Pressure control")  # display some text
            @c CImGui.DragInt("kPa", &f, 0.5, -20, 25)  # edit 1 float using a slider from 0 to 1
            
            CImGui.End()
        end

        @cstatic position=Cint(0) home=Cint(0) work=Cint(0) velocity=Cint(0) begin

            CImGui.Begin("Focus control")
            @c CImGui.Checkbox("Use controller", &use_controller) 
            if (CImGui.Button("Position: $position"))
                position = Cint(fetch(@spawnat pid getposition()))
            end
            
            if (CImGui.Button("Set Home: $home"))
                position = Cint(fetch(@spawnat pid getposition()))
                home = position
            end

            if (CImGui.Button("Set Work: $work"))
                position = Cint(fetch(@spawnat pid getposition()))
                work = position
            end

            if (CImGui.Button("Go Home"))
                @spawnat pid moveto(home)
            end

            if (CImGui.Button("Go Work"))
                @spawnat pid moveto(work)
            end
            
            if !use_controller
            @c CImGui.DragInt("Axis Velocity", &velocity, 1.0, -2000, 2000)
            end

            if use_controller
                axes_state = GLFW.GetJoystickAxes(ps1)
                up_raw = (axes_state[3] + 1.0) / 2
                down_raw = (axes_state[6] + 1.0) / 2

                up = round(up_raw, digits = 1)
                down = round(down_raw, digits = 1)

                velocity = Int32(round(Int, ((down - up) * 20000)))
                CImGui.Text("Velocity: $velocity")
            end
            
            if (CImGui.Button("STOPPP!!!!!"))
               velocity = Int32(0)
            end

            @spawnat pid set_velocity(Int32(velocity*100))
            CImGui.End()
        end
        
        CImGui.Begin("Vm Data")
        if (CImPlot.BeginPlot("Data", "","",CImGui.ImVec2(-1,700), CImPlot.LibCImPlot.ImPlotFlags_Default, CImPlot.LibCImPlot.ImPlotAxisFlags_Default,  CImPlot.LibCImPlot.ImPlotAxisFlags_Default))
            CImPlot.Plot(v_sig, offset = 1, stride = 2*10, label = "Vm")
            CImPlot.EndPlot()
        end
        CImGui.End()
       
        CImGui.Begin("XII Data")
        if (CImPlot.BeginPlot("Data", "","",CImGui.ImVec2(-1,400), CImPlot.LibCImPlot.ImPlotFlags_Default, CImPlot.LibCImPlot.ImPlotAxisFlags_Default,  CImPlot.LibCImPlot.ImPlotAxisFlags_Default))
            CImPlot.Plot(v_sig, offset = 0, stride = 2*10, label = "Vm")
            CImPlot.EndPlot()
        end
        CImGui.End()
        # rendering
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
catch e
    @error "Error in renderloop!" exception=e
    Base.show_backtrace(stderr, catch_backtrace())
finally
    ImGui_ImplOpenGL3_Shutdown()
    ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(ctx)
    GLFW.DestroyWindow(window)
    @spawnat pid stop(task)
end

end # module
