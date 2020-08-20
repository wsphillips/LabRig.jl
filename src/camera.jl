
module Camera

using ..CImGui.OpenGLBackend.ModernGL
using PVCAM
export ImagePipeline

mutable struct ImagePipeline
    histogram::Vector{Int32}
    cdf::Vector{Int32}
    out::Array{<:Union{UInt8,UInt16}}
    bitdepth::Integer
    target_bitdepth::Integer
    function ImagePipeline(x::Array{<:Union{UInt8,UInt16}}; bitdepth = 2^12, target_bitdepth = 2^16)
        histogram = zeros(Int32, bitdepth)
        cdf = zeros(Int32, bitdepth)
        out = similar(x)
        new(histogram, cdf, out, bitdepth, target_bitdepth)
    end
end

function gen_textures(num::Integer)
    result = UInt32[0 for i in 1:num]
    glGenTextures(num, result)
    any(i -> i <= 0, result) && error("glGenTextures returned an invalid id. OpenGL context active/current?")
    return result
end

function load_texture(tex_id::UInt32, img::Vector{UInt16}, height::Integer, width::Integer)
    glBindTexture(GL_TEXTURE_2D, tex_id)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_RED)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_RED)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, GL_RED)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glTexImage2D(GL_TEXTURE_2D, GLint(0), GL_RGB, Cint(width), Cint(height), GLint(0), GL_RED, GL_UNSIGNED_SHORT, img)
end

function reload_texture(tex_id, img::Vector{UInt16}, height, width)
    glBindTexture(GL_TEXTURE_2D, tex_id)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, Cint(width), Cint(height), GL_RED, GL_UNSIGNED_SHORT, img)
end

function make_histogram!(x, hist_out)
    fill!(hist_out, zero(Int32))
    @simd for i in x
        hist_out[i+1] += 1
    end
end

function equalize!(img, out, cdf, histogram, bitdepth)
    pixels = length(img)
    cdf .= round.(Int, cumsum(histogram) ./ pixels .* (bitdepth - 1))
    for i in 1:length(img)
        out[i] = cdf[img[i]+1]
    end
end

function (pipe::ImagePipeline)(img::Array)
    make_histogram!(img, pipe.histogram)
    equalize!(img, pipe.out, pipe.cdf, pipe.histogram, pipe.target_bitdepth)
end

end

