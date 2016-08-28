using Knet, CUDArt
libknet8handle = Libdl.dlopen(Libdl.find_library(["libknet8"],[Pkg.dir("Knet/src")]))

SIZE = 100000
ITER = 100000
x32 = KnetArray(rand(Float32,SIZE))
y32 = similar(x32)
s32 = rand(Float32)
x64 = KnetArray(rand(Float64,SIZE))
y64 = similar(x64)
s64 = rand(Float64)

function cuda01test(fname, jname=fname, o...)
    println(fname)
    fcpu = eval(parse(jname))
    f32 = Libdl.dlsym(libknet8handle, fname*"_32_01")
    @time cuda01rep(f32,s32,x32,y32)
    isapprox(to_host(y32),fcpu(s32,to_host(x32))) || warn("$fname 32")
    f64 = Libdl.dlsym(libknet8handle, fname*"_64_01")
    @time cuda01rep(f64,s64,x64,y64)
    isapprox(to_host(y64),fcpu(s64,to_host(x64))) || warn("$fname 64")
end

function cuda01rep{T}(f,s::T,x::KnetArray{T},y::KnetArray{T})
    n = Cint(length(y))
    for i=1:ITER
        ccall(f,Void,(Cint,T,Ptr{T},Ptr{T}),n,s,x,y)
    end
    device_synchronize()
    CUDArt.rt.checkerror(CUDArt.rt.cudaGetLastError())
end

for f in Knet.cuda01
    isa(f,Tuple) || (f=(f,))
    cuda01test(f...)
end
