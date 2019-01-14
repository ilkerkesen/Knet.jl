using LinearAlgebra

import Base: *, transpose, adjoint, permutedims, size, axes, IndexStyle
# import Base: A_mul_B!
# import Base: A_mul_Bt, A_mul_Bt!, A_mul_Bc, A_mul_Bc!
# import Base: At_mul_B, At_mul_B!, Ac_mul_B, Ac_mul_B!
# import Base: At_mul_Bt, At_mul_Bt!, Ac_mul_Bc, Ac_mul_Bc!
import LinearAlgebra.BLAS: gemm!, scal!
import LinearAlgebra: rmul!, lmul!, axpy!
# import Base.LinAlg: scale! `scale!(a::Number, B::AbstractArray)` is deprecated, use `lmul!(a, B)` instead.
export axpy!

# AutoGrad defines: @primitive1 *(x1,x2),dy  (dy*x2')  (x1'*dy)
# We specialize it below to avoid transposes
# Full-scale lazy transpose requires a lot more things to work with Adjoint(::KnetArray)
(*)(A::KnetMatrix{T},B::KnetMatrix{T}) where {T} = gemm!('N','N',one(T),A,B,zero(T),similar(A,(size(A,1),size(B,2))))
A_mul_Bt(A::KnetMatrix{T}, B::KnetMatrix{T}) where {T} = gemm!('N','T',one(T),A,B,zero(T),similar(A,size(A,1),size(B,1)))
At_mul_B(A::KnetMatrix{T}, B::KnetMatrix{T}) where {T} = gemm!('T','N',one(T),A,B,zero(T),similar(A,size(A,2),size(B,2)))
@primitive1 *(x1::KnetMatrix,x2::KnetMatrix),dy  A_mul_Bt(dy,x2)  At_mul_B(x1,dy)
@primitive1 Knet.A_mul_Bt(x1::KnetMatrix,x2::KnetMatrix),dy  (dy*x2)  At_mul_B(x1,dy)
@primitive1 Knet.At_mul_B(x1::KnetMatrix,x2::KnetMatrix),dy  A_mul_Bt(dy,x2)  (x1*dy)

# deprecated:
# A_mul_B!{T}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=gemm!('N','N',one(T),A,B,zero(T),C)
# A_mul_Bt!{T}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=gemm!('N','T',one(T),A,B,zero(T),C)
# A_mul_Bt{T}(A::KnetMatrix{T}, B::KnetMatrix{T})=A_mul_Bt!(similar(A,(size(A,1),size(B,1))),A,B)
# A_mul_Bc!{T<:Real}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=A_mul_Bt!(C,A,B)
# A_mul_Bc{T<:Real}(A::KnetMatrix{T}, B::KnetMatrix{T})=A_mul_Bt(A,B)

# At_mul_B!{T}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=gemm!('T','N',one(T),A,B,zero(T),C)
# At_mul_B{T}(A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_B!(similar(A,(size(A,2),size(B,2))),A,B)
# Ac_mul_B!{T<:Real}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_B!(C,A,B)
# Ac_mul_B{T<:Real}(A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_B(A,B)

# At_mul_Bt!{T}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=gemm!('T','T',one(T),A,B,zero(T),C)
# At_mul_Bt{T}(A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_Bt!(similar(A,(size(A,2),size(B,1))),A,B)
# Ac_mul_Bc!{T<:Real}(C::KnetMatrix{T}, A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_Bt!(C,A,B)
# Ac_mul_Bc{T<:Real}(A::KnetMatrix{T}, B::KnetMatrix{T})=At_mul_Bt(A,B)


function gemm!(transA::AbstractChar, transB::AbstractChar, alpha::Number, A::KnetArray{T}, B::KnetArray{T}, beta::Number, C::KnetArray{T}) where {T}
    cublasop(c::Char)=(if c=='N'; 0; elseif c=='T'; 1; elseif c=='C'; 2; else error("Unknown cublas op $c"); end)
    size2(x,i)=(if ndims(x)<=2; size(x,i); elseif i==1; div(length(x),size(x,ndims(x))); elseif i==2; size(x,ndims(x)); else 1; end)
    if transA == 'N'
        m=size2(A,1); k=size2(A,2)
    else
        m=size2(A,2); k=size2(A,1)
    end
    if transB == 'N'
        n=size2(B,2); k==size2(B,1) || throw(DimensionMismatch("$(map(size,(A,B,C)))"))
    else
        n=size2(B,1); k==size2(B,2) || throw(DimensionMismatch("$(map(size,(A,B,C)))"))
    end
    (m == size2(C,1) && n == size(C,2)) || throw(DimensionMismatch("$(map(size,(A,B,C)))"))
    transa = cublasop(transA); transb = cublasop(transB)
    alpha = T[alpha]; beta = T[beta]
    lda = size2(A,1); ldb = size2(B,1); ldc = size2(C,1)
    if T<:Float64
        @cublas(cublasDgemm_v2, (Cptr, UInt32, UInt32, Cint, Cint, Cint, Ptr{T}, Ptr{T}, Cint, Ptr{T}, Cint, Ptr{T}, Ptr{T}, Cint), cublashandle(), transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc)
    elseif T<:Float32
        @cublas(cublasSgemm_v2, (Cptr, UInt32, UInt32, Cint, Cint, Cint, Ptr{T}, Ptr{T}, Cint, Ptr{T}, Cint, Ptr{T}, Ptr{T}, Cint), cublashandle(), transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc)
    # elseif T<:Float16
    #     @cublas(cublasHgemm, (Cptr, UInt32, UInt32, Cint, Cint, Cint, Ptr{T}, Ptr{T}, Cint, Ptr{T}, Cint, Ptr{T}, Ptr{T}, Cint), cublashandle(), transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc)
    else
        error("CUBLAS does not support $T")
    end
    return C
end

function axpy!(n::Integer, alpha::Number, x::KnetArray{T}, incx::Integer, y::KnetArray{T}, incy::Integer) where {T}
    length(x) == length(y) || throw(DimensionMismatch("$(map(size,(x,y)))"))
    alpha = T[alpha]
    if T<:Float32
        @cublas(cublasSaxpy_v2, (Cptr, Cint, Ptr{T}, Ptr{T}, Cint, Ptr{T}, Cint), cublashandle(), n, alpha, x, incx, y, incy)
    elseif T<:Float64
        @cublas(cublasDaxpy_v2, (Cptr, Cint, Ptr{T}, Ptr{T}, Cint, Ptr{T}, Cint), cublashandle(), n, alpha, x, incx, y, incy)
    else
        error("$T not supported")
    end
    return y
end

axpy!(alpha::Number, x::KnetArray{T}, y::KnetArray{T}) where {T} = axpy!(length(x),alpha,x,1,y,1)


function scal!(n::Integer, alpha::Number, x::KnetArray{T}, incx::Integer) where {T}
    alpha = T[alpha]
    if T<:Float32
        @cublas(cublasSscal_v2, (Cptr, Cint, Ptr{T}, Ptr{T}, Cint), cublashandle(), n, alpha, x, incx)
    elseif T<:Float64
        @cublas(cublasDscal_v2, (Cptr, Cint, Ptr{T}, Ptr{T}, Cint), cublashandle(), n, alpha, x, incx)
    else
        error("$T not supported")
    end
    return x
end

lmul!(alpha::Number, x::KnetArray{T}) where {T} = scal!(length(x),alpha,x,1)
rmul!(x::KnetArray{T}, alpha::Number) where {T} = scal!(length(x),alpha,x,1)

transpose(x::KnetArray)=_transpose(x)
adjoint(x::KnetArray)=_transpose(x)

#= TODO: use the lazy transpose:
using LinearAlgebra: Adjoint, Transpose, AdjOrTrans
transpose(x::KnetArray)=Transpose(x)
adjoint(x::KnetArray)=Adjoint(x)
const AdjointKnetVec{T} = Adjoint{T,<:KnetVector}
const TransposeKnetVec{T} = Transpose{T,<:KnetVector}
const AdjOrTransKnetVec{T} = AdjOrTrans{T,<:KnetVector}
const AdjOrTransKnetMat{T} = AdjOrTrans{T,<:KnetMatrix}
size(v::AdjOrTransKnetVec) = (1, length(v.parent))
size(A::AdjOrTransKnetMat) = reverse(size(A.parent))
axes(v::AdjOrTransKnetVec) = (Base.OneTo(1), axes(v.parent)...)
axes(A::AdjOrTransKnetMat) = reverse(axes(A.parent))
IndexStyle(::Type{<:AdjOrTransKnetVec}) = IndexLinear()
IndexStyle(::Type{<:AdjOrTransKnetMat}) = IndexCartesian()
=#

function _transpose(x::KnetArray{T}) where {T} # trying the lazy version first
    ndims(x) != 2 && error("Transpose is supported only for 2D KnetArrays")
    # Using CUBLAS
    sz = size(x)
    y = similar(x,(sz[2],sz[1]))
    if T<:Float32
        @cublas(cublasSgeam, (Cptr,UInt32,UInt32,Cint,Cint,Ptr{T},Ptr{T},Cint,Ptr{T},Ptr{T},Cint,Ptr{T},Cint),
              cublashandle(),1,1,size(y,1),size(y,2),Ref(T(1.0)),x,size(x,1),Ref(T(0.0)),x,size(x,1),y,size(y,1))
    elseif T<:Float64
        @cublas(cublasDgeam, (Cptr,UInt32,UInt32,Cint,Cint,Ptr{T},Ptr{T},Cint,Ptr{T},Ptr{T},Cint,Ptr{T},Cint),
              cublashandle(),1,1,size(y,1),size(y,2),Ref(T(1.0)),x,size(x,1),Ref(T(0.0)),x,size(x,1),y,size(y,1))
    else
        error("CUBLAS does not support $T")
    end
    # Using CUDA kernel; performs worse than CUBLAS
    # y = permutedims(x,[2 1])
    return y
end


"""

    mat(x)

Reshape x into a two-dimensional matrix.

This is typically used when turning the output of a 4-D convolution
result into a 2-D input for a fully connected layer.  For 1-D inputs
returns `reshape(x, (length(x),1))`.  For inputs with more than two
dimensions of size `(X1,X2,...,XD)`, returns

    reshape(x, (X1*X2*...*X[D-1],XD))

"""
function mat(x)
    if ndims(x) > 2
        xn = size(x,ndims(x))
        reshape(x, (div(length(x),xn),xn))
    elseif ndims(x)==2
        x
    elseif ndims(x)==1
        reshape(x, (length(x),1))
    else
        throw(MethodError(mat,x))
    end
end


import Base: permutedims # ipermutedims

permutedims(x::KnetMatrix)=permutedims(x,(2,1))

function permutedims(x::KnetArray{T,N}, dims) where {T,N}
    if length(dims) != N; throw(DimensionMismatch()); end
    if N == 2
        # use individual == to cover row col vecs tuples etc
        if dims[1]==1 && dims[2]==2
            return copy(x)
        elseif dims[1]==2 && dims[2]==1
            # Using CUBLAS
            return _transpose(x)
        else
            throw(ArgumentError("no valid permutation of dimensions"))
        end
    else
        ca = Array(x)
        pa = permutedims(ca, dims)
        return KnetArray(pa)
    end
end

# Low level gemm! call with pointers: CPU conv4 uses this. Based on julia/stdlib/v1.0/LinearAlgebra/src/blas.jl:1105

using LinearAlgebra
using LinearAlgebra.BLAS: libblas, BlasInt
using LinearAlgebra.BLAS: @blasfunc

# C := alpha*op(A)*op(B) + beta*C, where:
# op(X) is one of op(X) = X, or op(X) = XT, or op(X) = XH,
# alpha and beta are scalars,
# A, B and C are matrices:
# op(A) is an m-by-k matrix,
# op(B) is a k-by-n matrix,
# C is an m-by-n matrix.

for (gemm, elty) in ((:dgemm_,:Float64), (:sgemm_,:Float32))
    @eval begin
        function gemm!(transA::AbstractChar, transB::AbstractChar, M::Int, N::Int, K::Int, alpha::($elty), A::Ptr{$elty}, B::Ptr{$elty}, beta::($elty), C::Ptr{$elty})
            if transA=='N'; lda=M; else; lda=K; end
            if transB=='N'; ldb=K; else; ldb=N; end
            ldc = M;
            # ccall((@blasfunc($gemm), libblas), Nothing,
            #       (Ptr{UInt8}, Ptr{UInt8}, Ptr{BlasInt}, Ptr{BlasInt},
            #        Ptr{BlasInt}, Ptr{$elty}, Ptr{$elty}, Ptr{BlasInt},
            #        Ptr{$elty}, Ptr{BlasInt}, Ptr{$elty}, Ptr{$elty},
            #        Ptr{BlasInt}),
            #       &transA, &transB, &M, &N, &K,
            #       &alpha, A, &lda, B, &ldb, &beta, C, &ldc)

            ccall((@blasfunc($gemm), libblas), Cvoid,
                  (Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt},
                   Ref{BlasInt}, Ref{$elty}, Ptr{$elty}, Ref{BlasInt},
                   Ptr{$elty}, Ref{BlasInt}, Ref{$elty}, Ptr{$elty},
                   Ref{BlasInt}),
                  transA, transB, M, N, K,
                  alpha, A, lda,
                  B, ldb,
                  beta, C, ldc)
        end
    end
end
