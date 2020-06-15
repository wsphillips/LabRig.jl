
# OpenGL 3.0 + GLSL 130
const glsl_version = 130
GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 0)

# setup GLFW error callback
error_callback(err::GLFW.GLFWError) = @error "GLFW ERROR: code $(err.code) msg: $(err.description)"
GLFW.SetErrorCallback(error_callback)

# create window
window = GLFW.CreateWindow(1280, 720, "LabRig")
@assert window != C_NULL
GLFW.MakeContextCurrent(window)
GLFW.SwapInterval(1)  # enable vsync

# setup Dear ImGui context
ctx = CImGui.CreateContext()

# setup Dear ImGui style
CImGui.StyleColorsDark()

# load Fonts
fonts_dir = joinpath(@__DIR__, "..", "fonts")
fonts = CImGui.GetIO().Fonts
CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Roboto-Medium.ttf"), 16)

# setup Platform/Renderer bindings
ImGui_ImplGlfw_InitForOpenGL(window, true)
ImGui_ImplOpenGL3_Init(glsl_version)

