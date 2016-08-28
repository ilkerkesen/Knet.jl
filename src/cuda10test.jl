using Knet,CUDArt
libknet8handle = Libdl.dlopen(Libdl.find_library(["libknet8"],[Pkg.dir("Knet/src")]))

SIZE = 100000
ITER = 100000
x32 = KnetArray(rand(Float32,SIZE))
y32 = similar(x32)
s32 = rand(Float32)
x64 = KnetArray(rand(Float64,SIZE))
y64 = similar(x64)
s64 = rand(Float64)

function cuda10test(fname, jname=fname, o...)
    println(fname)
    fcpu = eval(parse(jname))
    f32 = Libdl.dlsym(libknet8handle, fname*"_32_10")
    @time cuda10rep(f32,x32,s32,y32)
    isapprox(to_host(y32),fcpu(to_host(x32),s32)) || warn("$fname 32")
    f64 = Libdl.dlsym(libknet8handle, fname*"_64_10")
    @time cuda10rep(f64,x64,s64,y64)
    isapprox(to_host(y64),fcpu(to_host(x64),s64)) || warn("$fname 64")
end

function cuda10rep{T}(f,x::KnetArray{T},s::T,y::KnetArray{T})
    n = Cint(length(y))
    for i=1:ITER
        ccall(f,Void,(Cint,Ptr{T},T,Ptr{T}),n,x,s,y)
    end
    device_synchronize()
    CUDArt.rt.checkerror(CUDArt.rt.cudaGetLastError())
end

for f in Knet.cuda10
    isa(f,Tuple) || (f=(f,))
    cuda10test(f...)
    cuda10test(f...)
    cuda10test(f...)
end
