# This file is a part of Julia. License is MIT: https://julialang.org/license

using  Base.MultiplicativeInverses: SignedMultiplicativeInverse

struct ReshapedArray{T,N,P<:AbstractArray,MI<:Tuple{Vararg{SignedMultiplicativeInverse{Int}}}} <: AbstractArray{T,N}
    parent::P
    dims::NTuple{N,Int}
    mi::MI
end
ReshapedArray(parent::AbstractArray{T}, dims::NTuple{N,Int}, mi) where {T,N} = ReshapedArray{T,N,typeof(parent),typeof(mi)}(parent, dims, mi)

# IndexLinear ReshapedArray
const ReshapedArrayLF{T,N,P<:AbstractArray} = ReshapedArray{T,N,P,Tuple{}}

# Fast iteration on ReshapedArrays: use the parent iterator
struct ReshapedArrayIterator{I,M}
    iter::I
    mi::NTuple{M,SignedMultiplicativeInverse{Int}}
end
ReshapedArrayIterator(A::ReshapedArray) = _rs_iterator(parent(A), A.mi)
function _rs_iterator(P, mi::NTuple{M}) where M
    iter = eachindex(P)
    ReshapedArrayIterator{typeof(iter),M}(iter, mi)
end

struct ReshapedIndex{T}
    parentindex::T
end

# eachindex(A::ReshapedArray) = ReshapedArrayIterator(A)  # TODO: uncomment this line
@inline function iterate(R::ReshapedArrayIterator, i...)
    item, inext = iterate(R.iter, i...)
    ReshapedIndex(item), inext
end
length(R::ReshapedArrayIterator) = length(R.iter)
eltype(::Type{<:ReshapedArrayIterator{I}}) where {I} = @isdefined(I) ? ReshapedIndex{eltype(I)} : Any

@noinline throw_dmrsa(dims, len) =
    throw(DimensionMismatch(LazyString("new dimensions ", dims, " must be consistent with array length ", len)))

## reshape(::Array, ::Dims) returns a new Array (to avoid conditionally aliasing the structure, only the data)
# reshaping to same # of dimensions
@eval function reshape(a::Array{T,M}, dims::NTuple{N,Int}) where {T,N,M}
    len = Core.checked_dims(dims...) # make sure prod(dims) doesn't overflow (and because of the comparison to length(a))
    if len != length(a)
        throw_dmrsa(dims, length(a))
    end
    ref = a.ref
    # or we could use `a = Array{T,N}(undef, ntuple(i->0, Val(N))); a.ref = ref; a.size = dims; return a` here to avoid the eval
    return $(Expr(:new, :(Array{T,N}), :ref, :dims))
end

## reshape!(::Array, ::Dims) returns the original array, but must have the same dimensions and length as the original
# see also resize! for a similar operation that can change the length
function reshape!(a::Array{T,N}, dims::NTuple{N,Int}) where {T,N}
    len = Core.checked_dims(dims...) # make sure prod(dims) doesn't overflow (and because of the comparison to length(a))
    if len != length(a)
        throw_dmrsa(dims, length(a))
    end
    setfield!(a, :dims, dims)
    return a
end



"""
    reshape(A, dims...)::AbstractArray
    reshape(A, dims)::AbstractArray

Return an array with the same data as `A`, but with different
dimension sizes or number of dimensions. The two arrays share the same
underlying data, so that the result is mutable if and only if `A` is
mutable, and setting elements of one alters the values of the other.

The new dimensions may be specified either as a list of arguments or
as a shape tuple. At most one dimension may be specified with a `:`,
in which case its length is computed such that its product with all
the specified dimensions is equal to the length of the original array
`A`. The total number of elements must not change.

# Examples
```jldoctest
julia> A = Vector(1:16)
16-element Vector{Int64}:
  1
  2
  3
  4
  5
  6
  7
  8
  9
 10
 11
 12
 13
 14
 15
 16

julia> reshape(A, (4, 4))
4×4 Matrix{Int64}:
 1  5   9  13
 2  6  10  14
 3  7  11  15
 4  8  12  16

julia> reshape(A, 2, :)
2×8 Matrix{Int64}:
 1  3  5  7   9  11  13  15
 2  4  6  8  10  12  14  16

julia> reshape(1:6, 2, 3)
2×3 reshape(::UnitRange{Int64}, 2, 3) with eltype Int64:
 1  3  5
 2  4  6
```
"""
reshape

reshape(parent::AbstractArray, dims::IntOrInd...) = reshape(parent, dims)
reshape(parent::AbstractArray, shp::Tuple{Union{Integer,AbstractOneTo}, Vararg{Union{Integer,AbstractOneTo}}}) = reshape(parent, to_shape(shp))
# legacy method for packages that specialize reshape(parent::AbstractArray, shp::Tuple{Union{Integer,OneTo,CustomAxis}, Vararg{Union{Integer,OneTo,CustomAxis}}})
# leaving this method in ensures that Base owns the more specific method
reshape(parent::AbstractArray, shp::Tuple{Union{Integer,OneTo}, Vararg{Union{Integer,OneTo}}}) = reshape(parent, to_shape(shp))
reshape(parent::AbstractArray, dims::Tuple{Integer, Vararg{Integer}}) = reshape(parent, map(Int, dims))
reshape(parent::AbstractArray, dims::Dims)        = _reshape(parent, dims)

# Allow missing dimensions with Colon():
reshape(parent::AbstractVector, ::Colon) = parent
reshape(parent::AbstractVector, ::Tuple{Colon}) = parent
reshape(parent::AbstractArray, dims::Int...) = reshape(parent, dims)
reshape(parent::AbstractArray, dims::Integer...) = reshape(parent, dims)
reshape(parent::AbstractArray, dims::Union{Integer,Colon}...) = reshape(parent, dims)
reshape(parent::AbstractArray, dims::Tuple{Vararg{Union{Integer,Colon}}}) = reshape(parent, _reshape_uncolon(parent, dims))

@noinline throw1(dims) = throw(DimensionMismatch(LazyString("new dimensions ", dims,
        " may have at most one omitted dimension specified by `Colon()`")))
@noinline throw2(lenA, dims) = throw(DimensionMismatch(string("array size ", lenA,
    " must be divisible by the product of the new dimensions ", dims)))

@inline function _reshape_uncolon(A, _dims::Tuple{Vararg{Union{Integer, Colon}}})
    # promote the dims to `Int` at least
    dims = map(x -> x isa Colon ? x : promote_type(typeof(x), Int)(x), _dims)
    pre = _before_colon(dims...)
    post = _after_colon(dims...)
    _any_colon(post...) && throw1(dims)
    len = length(A)
    _reshape_uncolon_computesize(len, dims, pre, post)
end
@inline function _reshape_uncolon_computesize(len::Int, dims, pre::Tuple{Vararg{Int}}, post::Tuple{Vararg{Int}})
    sz = if iszero(len)
        0
    else
        let pr = Core.checked_dims(pre..., post...)  # safe product
            quo = _reshape_uncolon_computesize_nonempty(len, dims, pr)
            convert(Int, quo)
        end
    end
    (pre..., sz, post...)
end
@inline function _reshape_uncolon_computesize(len, dims, pre, post)
    pr = prod((pre..., post...))
    sz = if iszero(len)
        promote(len, pr)[1] # zero of the correct type
    else
        _reshape_uncolon_computesize_nonempty(len, dims, pr)
    end
    (pre..., sz, post...)
end
@inline function _reshape_uncolon_computesize_nonempty(len, dims, pr)
    iszero(pr) && throw2(len, dims)
    (quo, rem) = divrem(len, pr)
    iszero(rem) || throw2(len, dims)
    quo
end
@inline _any_colon() = false
@inline _any_colon(dim::Colon, tail...) = true
@inline _any_colon(dim::Any, tail...) = _any_colon(tail...)
@inline _before_colon(dim::Any, tail...) = (dim, _before_colon(tail...)...)
@inline _before_colon(dim::Colon, tail...) = ()
@inline _after_colon(dim::Any, tail...) =  _after_colon(tail...)
@inline _after_colon(dim::Colon, tail...) = tail

reshape(parent::AbstractArray{T,N}, ndims::Val{N}) where {T,N} = parent
function reshape(parent::AbstractArray, ndims::Val{N}) where N
    reshape(parent, rdims(Val(N), axes(parent)))
end

# Move elements from inds to out until out reaches the desired
# dimensionality N, either filling with OneTo(1) or collapsing the
# product of trailing dims into the last element
rdims_trailing(l, inds...) = length(l) * rdims_trailing(inds...)
rdims_trailing(l) = length(l)
rdims(out::Val{N}, inds::Tuple) where {N} = rdims(ntuple(Returns(OneTo(1)), Val(N)), inds)
rdims(out::Tuple{}, inds::Tuple{}) = () # N == 0, M == 0
rdims(out::Tuple{}, inds::Tuple{Any}) = ()
rdims(out::Tuple{}, inds::NTuple{M,Any}) where {M} = ()
rdims(out::Tuple{Any}, inds::Tuple{}) = out # N == 1, M == 0
rdims(out::NTuple{N,Any}, inds::Tuple{}) where {N} = out # N > 1, M == 0
rdims(out::Tuple{Any}, inds::Tuple{Any}) = inds # N == 1, M == 1
rdims(out::Tuple{Any}, inds::NTuple{M,Any}) where {M} = (oneto(rdims_trailing(inds...)),) # N == 1, M > 1
rdims(out::NTuple{N,Any}, inds::NTuple{N,Any}) where {N} = inds # N > 1, M == N
rdims(out::NTuple{N,Any}, inds::NTuple{M,Any}) where {N,M} = (first(inds), rdims(tail(out), tail(inds))...) # N > 1, M > 1, M != N


# _reshape on Array returns an Array
_reshape(parent::Vector, dims::Dims{1}) = parent
_reshape(parent::Array, dims::Dims{1}) = reshape(parent, dims)
_reshape(parent::Array, dims::Dims) = reshape(parent, dims)

# When reshaping Vector->Vector, don't wrap with a ReshapedArray
function _reshape(v::AbstractVector, dims::Dims{1})
    require_one_based_indexing(v)
    len = dims[1]
    len == length(v) || _throw_dmrs(length(v), "length", len)
    v
end
# General reshape
function _reshape(parent::AbstractArray, dims::Dims)
    n = length(parent)
    prod(dims) == n || _throw_dmrs(n, "size", dims)
    __reshape((parent, IndexStyle(parent)), dims)
end

@noinline function _throw_dmrs(n, str, dims)
    throw(DimensionMismatch("parent has $n elements, which is incompatible with $str $dims ($(prod(dims)) elements)"))
end

# Reshaping a ReshapedArray
_reshape(v::ReshapedArray{<:Any,1}, dims::Dims{1}) = _reshape(v.parent, dims)
_reshape(R::ReshapedArray, dims::Dims) = _reshape(R.parent, dims)

function __reshape(p::Tuple{AbstractArray,IndexStyle}, dims::Dims)
    parent = p[1]
    strds = front(size_to_strides(map(length, axes(parent))..., 1))
    strds1 = map(s->max(1,Int(s)), strds)  # for resizing empty arrays
    mi = map(SignedMultiplicativeInverse, strds1)
    ReshapedArray(parent, dims, reverse(mi))
end

function __reshape(p::Tuple{AbstractArray{<:Any,0},IndexCartesian}, dims::Dims)
    parent = p[1]
    ReshapedArray(parent, dims, ())
end

function __reshape(p::Tuple{AbstractArray,IndexLinear}, dims::Dims)
    parent = p[1]
    ReshapedArray(parent, dims, ())
end

size(A::ReshapedArray) = A.dims
length(A::ReshapedArray) = length(parent(A))
similar(A::ReshapedArray, eltype::Type, dims::Dims) = similar(parent(A), eltype, dims)
IndexStyle(::Type{<:ReshapedArrayLF}) = IndexLinear()
parent(A::ReshapedArray) = A.parent
parentindices(A::ReshapedArray) = map(oneto, size(parent(A)))
reinterpret(::Type{T}, A::ReshapedArray, dims::Dims) where {T} = reinterpret(T, parent(A), dims)
elsize(::Type{<:ReshapedArray{<:Any,<:Any,P}}) where {P} = elsize(P)

unaliascopy(A::ReshapedArray) = typeof(A)(unaliascopy(A.parent), A.dims, A.mi)
dataids(A::ReshapedArray) = dataids(A.parent)
# forward the aliasing check the parent in case there are specializations
mightalias(A::ReshapedArray, B::ReshapedArray) = mightalias(parent(A), parent(B))
# special handling for reshaped SubArrays that dispatches to the subarray aliasing check
mightalias(A::ReshapedArray, B::SubArray) = mightalias(parent(A), B)
mightalias(A::SubArray, B::ReshapedArray) = mightalias(A, parent(B))

@inline ind2sub_rs(ax, ::Tuple{}, i::Int) = (i,)
@inline ind2sub_rs(ax, strds, i) = _ind2sub_rs(ax, strds, i - 1)
@inline _ind2sub_rs(ax, ::Tuple{}, ind) = (ind + first(ax[end]),)
@inline function _ind2sub_rs(ax, strds, ind)
    d, r = divrem(ind, strds[1])
    (_ind2sub_rs(front(ax), tail(strds), r)..., d + first(ax[end]))
end
offset_if_vec(i::Integer, axs::Tuple{<:AbstractUnitRange}) = i + first(axs[1]) - 1
offset_if_vec(i::Integer, axs::Tuple) = i

@inline function isassigned(A::ReshapedArrayLF, index::Int)
    @boundscheck checkbounds(Bool, A, index) || return false
    indexparent = index - firstindex(A) + firstindex(parent(A))
    @inbounds ret = isassigned(parent(A), indexparent)
    ret
end
@inline function isassigned(A::ReshapedArray{T,N}, indices::Vararg{Int, N}) where {T,N}
    @boundscheck checkbounds(Bool, A, indices...) || return false
    axp = axes(A.parent)
    i = offset_if_vec(_sub2ind(size(A), indices...), axp)
    I = ind2sub_rs(axp, A.mi, i)
    @inbounds isassigned(A.parent, I...)
end

@inline function getindex(A::ReshapedArrayLF, index::Int)
    @boundscheck checkbounds(A, index)
    indexparent = index - firstindex(A) + firstindex(parent(A))
    @inbounds ret = parent(A)[indexparent]
    ret
end
@inline function getindex(A::ReshapedArray{T,N}, indices::Vararg{Int,N}) where {T,N}
    @boundscheck checkbounds(A, indices...)
    _unsafe_getindex(A, indices...)
end
@inline function getindex(A::ReshapedArray, index::ReshapedIndex)
    @boundscheck checkbounds(parent(A), index.parentindex)
    @inbounds ret = parent(A)[index.parentindex]
    ret
end

@inline function _unsafe_getindex(A::ReshapedArray{T,N}, indices::Vararg{Int,N}) where {T,N}
    axp = axes(A.parent)
    i = offset_if_vec(_sub2ind(size(A), indices...), axp)
    I = ind2sub_rs(axp, A.mi, i)
    _unsafe_getindex_rs(parent(A), I)
end
@inline _unsafe_getindex_rs(A, i::Integer) = (@inbounds ret = A[i]; ret)
@inline _unsafe_getindex_rs(A, I) = (@inbounds ret = A[I...]; ret)

@inline function setindex!(A::ReshapedArrayLF, val, index::Int)
    @boundscheck checkbounds(A, index)
    indexparent = index - firstindex(A) + firstindex(parent(A))
    @inbounds parent(A)[indexparent] = val
    val
end
@inline function setindex!(A::ReshapedArray{T,N}, val, indices::Vararg{Int,N}) where {T,N}
    @boundscheck checkbounds(A, indices...)
    _unsafe_setindex!(A, val, indices...)
end
@inline function setindex!(A::ReshapedArray, val, index::ReshapedIndex)
    @boundscheck checkbounds(parent(A), index.parentindex)
    @inbounds parent(A)[index.parentindex] = val
    val
end

@inline function _unsafe_setindex!(A::ReshapedArray{T,N}, val, indices::Vararg{Int,N}) where {T,N}
    axp = axes(A.parent)
    i = offset_if_vec(_sub2ind(size(A), indices...), axp)
    @inbounds parent(A)[ind2sub_rs(axes(A.parent), A.mi, i)...] = val
    val
end

# helpful error message for a common failure case
const ReshapedRange{T,N,A<:AbstractRange} = ReshapedArray{T,N,A,Tuple{}}
setindex!(A::ReshapedRange, val, index::Int) = _rs_setindex!_err()
setindex!(A::ReshapedRange{T,N}, val, indices::Vararg{Int,N}) where {T,N} = _rs_setindex!_err()
setindex!(A::ReshapedRange, val, index::ReshapedIndex) = _rs_setindex!_err()

@noinline _rs_setindex!_err() = error("indexed assignment fails for a reshaped range; consider calling collect")

cconvert(::Type{Ptr{T}}, a::ReshapedArray{T}) where {T} = cconvert(Ptr{T}, parent(a))
unsafe_convert(::Type{Ptr{T}}, a::ReshapedArray{T}) where {T} = unsafe_convert(Ptr{T}, a.parent)

# Add a few handy specializations to further speed up views of reshaped ranges
const ReshapedUnitRange{T,N,A<:AbstractUnitRange} = ReshapedArray{T,N,A,Tuple{}}
viewindexing(I::Tuple{Slice, ReshapedUnitRange, Vararg{ScalarIndex}}) = IndexLinear()
viewindexing(I::Tuple{ReshapedRange, Vararg{ScalarIndex}}) = IndexLinear()
compute_stride1(s, inds, I::Tuple{ReshapedRange, Vararg{Any}}) = s*step(I[1].parent)
compute_offset1(parent::AbstractVector, stride1::Integer, I::Tuple{ReshapedRange}) =
    (@inline; first(I[1]) - first(axes1(I[1]))*stride1)
substrides(strds::NTuple{N,Int}, I::Tuple{ReshapedUnitRange, Vararg{Any}}) where N =
    (size_to_strides(strds[1], size(I[1])...)..., substrides(tail(strds), tail(I))...)

# cconvert(::Type{<:Ptr}, V::SubArray{T,N,P,<:Tuple{Vararg{Union{RangeIndex,ReshapedUnitRange}}}}) where {T,N,P} = V
function unsafe_convert(::Type{Ptr{S}}, V::SubArray{T,N,P,<:Tuple{Vararg{Union{RangeIndex,ReshapedUnitRange}}}}) where {S,T,N,P}
    parent = V.parent
    p = cconvert(Ptr{T}, parent) # XXX: this should occur in cconvert, the result is not GC-rooted
    Δmem = if _checkcontiguous(Bool, parent)
        (first_index(V) - firstindex(parent)) * elsize(parent)
    else
        _memory_offset(parent, map(first, V.indices)...)
    end
    return Ptr{S}(unsafe_convert(Ptr{T}, p) + Δmem)
end

_checkcontiguous(::Type{Bool}, A::AbstractArray) = false
# `strides(A::DenseArray)` calls `size_to_strides` by default.
# Thus it's OK to assume all `DenseArray`s are contiguously stored.
_checkcontiguous(::Type{Bool}, A::DenseArray) = true
_checkcontiguous(::Type{Bool}, A::ReshapedArray) = _checkcontiguous(Bool, parent(A))
_checkcontiguous(::Type{Bool}, A::FastContiguousSubArray) = _checkcontiguous(Bool, parent(A))

function strides(a::ReshapedArray)
    _checkcontiguous(Bool, a) && return size_to_strides(1, size(a)...)
    apsz::Dims = size(a.parent)
    apst::Dims = strides(a.parent)
    msz, mst, n = merge_adjacent_dim(apsz, apst) # Try to perform "lazy" reshape
    n == ndims(a.parent) && return size_to_strides(mst, size(a)...) # Parent is stridevector like
    return _reshaped_strides(size(a), 1, msz, mst, n, apsz, apst)
end

function _reshaped_strides(::Dims{0}, reshaped::Int, msz::Int, ::Int, ::Int, ::Dims, ::Dims)
    reshaped == msz && return ()
    throw(ArgumentError("Input is not strided."))
end
function _reshaped_strides(sz::Dims, reshaped::Int, msz::Int, mst::Int, n::Int, apsz::Dims, apst::Dims)
    st = reshaped * mst
    reshaped = reshaped * sz[1]
    if length(sz) > 1 && reshaped == msz && sz[2] != 1
        msz, mst, n = merge_adjacent_dim(apsz, apst, n + 1)
        reshaped = 1
    end
    sts = _reshaped_strides(tail(sz), reshaped, msz, mst, n, apsz, apst)
    return (st, sts...)
end

merge_adjacent_dim(::Dims{0}, ::Dims{0}) = 1, 1, 0
merge_adjacent_dim(apsz::Dims{1}, apst::Dims{1}) = apsz[1], apst[1], 1
function merge_adjacent_dim(apsz::Dims{N}, apst::Dims{N}, n::Int = 1) where {N}
    sz, st = apsz[n], apst[n]
    while n < N
        szₙ, stₙ = apsz[n+1], apst[n+1]
        if sz == 1
            sz, st = szₙ, stₙ
        elseif stₙ == st * sz || szₙ == 1
            sz *= szₙ
        else
            break
        end
        n += 1
    end
    return sz, st, n
end
