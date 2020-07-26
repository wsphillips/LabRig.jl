
module Pipeline

export ImagePipeline

mutable struct ImagePipeline
    histogram::Vector{Int32}
    cdf::Vector{Int32}
    out::Array{<:Union{UInt8,UInt16}}
    bitdepth::Integer
    function ImagePipeline(x::Array{<:Union{UInt8,UInt16}}; bitdepth = 2^12)
        histogram = zeros(Int32, bitdepth)
        cdf = zeros(Int32, bitdepth)
        out = similar(x)
        new(histogram, cdf, out, bitdepth)
    end
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
        out[i] = ceil(cdf[img[i]+1])
    end
end

function (pipe::ImagePipeline)(img::Array)
    make_histogram!(img, pipe.histogram)
    equalize!(img, pipe.out, pipe.cdf, pipe.histogram, pipe.bitdepth)
end

end

