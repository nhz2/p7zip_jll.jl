using p7zip_jll
using CodecZlib
using CodecZstd
using CodecBzip2
using CodecXz
using TranscodingStreams
using SHA
using Test

run(`$(p7zip()) i`)
run(`$(p7zip()) b`)

struct MultiWriter <: IO
    writers::Vector{IO}
    hash_ctx::SHA2_256_CTX
end

Base.isopen(w::MultiWriter) = isopen(first(writers))
Base.isreadable(w::MultiWriter) = false
function Base.write(w::MultiWriter, x::UInt8)
    for io in w.writers
        write(io, x)
    end
    update!(w.hash_ctx, [x])
    1
end

function Base.unsafe_write(w::MultiWriter, p::Ptr{UInt8}, n::UInt)::Int
    for io in w.writers
        unsafe_write(io, p, n)
    end
    temp = zeros(UInt8, n)
    @ccall memcpy(temp::Ptr{UInt8}, p::Ptr{UInt8}, n::Csize_t)::Ptr{Cvoid}
    update!(w.hash_ctx, temp)
    n
end

function test_7z(f, encoder, decoder, p7zip_opt)
    mktemp() do p7z_path, p7z_io
        mktemp() do ts_path, ts_io
            ts_sink = TranscodingStream(encoder(), ts_io)
            local in_hash
            if isnothing(p7zip_opt)
                sink = MultiWriter(IO[ts_sink], SHA256_CTX())
                f(sink)
                close(ts_sink)
                in_hash = digest!(sink.hash_ctx)
            else
                open(`$(p7zip()) a -si -so $p7zip_opt -- $(tempname())`, p7z_io; write=true) do p7z_sink
                    sink = MultiWriter(IO[p7z_sink, ts_sink], SHA256_CTX())
                    f(sink)
                    close(ts_sink)
                    in_hash = digest!(sink.hash_ctx)
                end
                close(p7z_io)
            end
            if !isnothing(p7zip_opt)
                open(p7z_path) do io
                    local ts_source = TranscodingStream(decoder(), io)
                    local ts_out_hash = sha256(ts_source)
                    close(ts_source)
                    local p7z_out_hash = open(sha256, `$(p7zip()) x  -so -- $p7z_path`)
                    @test ts_out_hash == p7z_out_hash
                    @test ts_out_hash == in_hash
                end
            end
            open(ts_path) do io
                local ts_source = TranscodingStream(decoder(), io)
                local ts_out_hash = sha256(ts_source)
                close(ts_source)
                local p7z_out_hash = open(sha256, `$(p7zip()) x $ts_path -so`)
                @test ts_out_hash == p7z_out_hash
                @test ts_out_hash == in_hash
            end
        end
    end
    nothing
end

@testset "$encoder" for (encoder, decoder, p7zip_opt) in [
        (GzipCompressor, GzipDecompressor, "-tgzip"),
        (XzCompressor, XzDecompressor, "-txz"),
        (ZstdCompressor, ZstdDecompressor, nothing),
        (Bzip2Compressor, Bzip2Decompressor, "-tbzip2"),
    ]
    # Start with a run of zeros
    for i in 0:500
        test_7z(encoder, decoder, p7zip_opt) do io
            write(io, zeros(UInt8, i))
        end
    end
    # Exercise look back
    thing = rand(UInt8, 200)
    test_7z(encoder, decoder, p7zip_opt) do io
        for dist in [0:258; 1000:1030; 2000:1000:33000; 34000:10000:100_000]
            write(io, thing)
            write(io, rand(0x00:0x0f, dist))
        end
    end
    for n in 65536-300:65536-100
        test_7z(encoder, decoder, p7zip_opt) do io
            write(io, [thing; zeros(UInt8, n); thing])
        end
    end
    # 2^33 zeros
    @info "writing 2^31 zeros for $(encoder) this may take a while"
    test_7z(encoder, decoder, p7zip_opt) do io
        for i in 1:2^8
            # @info i
            write(io, zeros(UInt8, 2^23))
        end
    end
end
