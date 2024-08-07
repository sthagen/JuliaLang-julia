# This file is a part of Julia. License is MIT: https://julialang.org/license

# tests related to functional programming functions and styles

# map -- array.jl
@test isequal(map((x)->"$x"[end:end], 9:11), ["9", "0", "1"])
# TODO: @test map!() much more thoroughly
let a = [1.0, 2.0]
    map!(sin, a, a)
    @test isequal(a, sin.([1.0, 2.0]))
end
# map -- ranges.jl
@test isequal(map(sqrt, 1:5), [sqrt(i) for i in 1:5])
@test isequal(map(sqrt, 2:6), [sqrt(i) for i in 2:6])

# map on ranges should evaluate first value only once (#4453)
let io=IOBuffer(maxsize=3)
    map(x->print(io,x), 1:2)
    @test String(take!(io))=="12"
end

# map over Bottom[] should return Bottom[]
# issue #6719
@test isequal(typeof(map(x -> x, Vector{Union{}}(undef, 0))), Vector{Union{}})

# maps of tuples (formerly in test/core.jl) -- tuple.jl
@test map((x,y)->x+y,(1,2,3),(4,5,6)) == (5,7,9)
@test map((x,y)->x+y,
            (100001,100002,100003),
            (100004,100005,100006)) == (200005,200007,200009)

# maps of strings (character arrays) -- string.jl
@test map((c)->Char(c+1), "abcDEF") == "bcdEFG"

# issue #10633
@test isa(map(Integer, Any[1, 2]), Vector{Int})
@test isa(map(Integer, Any[]), Vector{Integer})

# issue #25433
@test @inferred(collect(v for v in [1] if v > 0)) isa Vector{Int}

# filter -- array.jl
@test isequal(filter(x->(x>1), [0 1 2 3 2 1 0]), [2, 3, 2])
# TODO: @test_throws isequal(filter(x->x+1, [0 1 2 3 2 1 0]), [2, 3, 2])
@test isequal(filter(x->(x>10), [0 1 2 3 2 1 0]), [])
@test isequal(filter((ss)->length(ss)==3, ["abcd", "efg", "hij", "klmn", "opq"]), ["efg", "hij", "opq"])

# numbers
@test size(collect(1)) == size(1)

@test isa(collect(Any, [1,2]), Vector{Any})

# foreach
let a = []
    foreach(x->push!(a,x), [1,5,10])
    @test a == [1,5,10]
    a = []
    foreach((args...)->push!(a,args), [2,4,6], [10,20,30])
    @test a == [(2,10),(4,20),(6,30)]
end

# generators (#4470, #14848)
@test sum(i/2 for i=1:2) == 1.5
@test collect(2i for i=2:5) == [4,6,8,10]
@test collect((i+10j for i=1:2,j=3:4)) == [31 41; 32 42]
@test collect((i+10j for i=1:2,j=3:4,k=1:1)) == reshape([31 41; 32 42], (2,2,1))

let A = collect(Base.Generator(x->2x, Real[1.5,2.5]))
    @test A == [3,5]
    @test isa(A,Vector{Float64})
end

let f(g) = (@test size(g.iter)==(2,3))
    f(i+j for i=1:2, j=3:5)
end

@test collect(Base.Generator(+, [1,2], [10,20])) == [11,22]

# generator ndims #16394
let gens_dims = [((i for i = 1:5),                    1),
                 ((i for i = 1:5, j = 1:5),           2),
                 ((i for i = 1:5, j = 1:5, k = 1:5),  3),
                 ((i for i = Array{Int,0}(undef)),           0),
                 ((i for i = Vector{Int}(undef, 1)),          1),
                 ((i for i = Matrix{Int}(undef, 1, 2)),       2),
                 ((i for i = Array{Int}(undef, 1, 2, 3)),    3)]
    for (gen, dim) in gens_dims
        @test ndims(gen) == ndims(collect(gen)) == dim
    end
end

# generator with destructuring
let d = Dict(:a=>1, :b=>2), a = Dict(3=>4, 5=>6)
    @test Dict( v=>(k,) for (k,v) in d) == Dict(2=>(:b,), 1=>(:a,))
    @test Dict( (x,b)=>(c,y) for (x,c) in d, (b,y) in a ) == Dict((:a,5)=>(1,6),(:b,5)=>(2,6),(:a,3)=>(1,4),(:b,3)=>(2,4))
end

let i = 1
    local g = (i+j for i=2:2, j=3:3)
    @test first(g) == 5
    @test i == 1
end

# generators and guards
let gen = (x for x in 1:10)
    @test gen.iter == 1:10
    @test gen.f(first(1:10)) == iterate(gen)[1]
    for (a,b) in zip(1:10,gen)
        @test a == b
    end
end

let gen = (x * y for x in 1:10, y in 1:10)
    @test collect(gen) == Vector(1:10) .* Vector(1:10)'
    @test first(gen) == 1
    @test collect(gen)[1:10] == 1:10
end

let gen = Base.Generator(+, 1:10, 1:10, 1:10)
    @test first(gen) == 3
    @test collect(gen) == 3:3:30
end

let gen = (x for x in 1:10 if x % 2 == 0), gen2 = Iterators.filter(x->x % 2 == 0, x for x in 1:10)
    @test collect(gen) == collect(gen2)
    @test collect(gen) == 2:2:10
end

let gen = ((x,y) for x in 1:10, y in 1:10 if x % 2 == 0 && y % 2 == 0),
    gen2 = Iterators.filter(x->x[1] % 2 == 0 && x[2] % 2 == 0, (x,y) for x in 1:10, y in 1:10)
    @test collect(gen) == collect(gen2)
end

# keys of a generator for find* and arg* (see #34678)
@test keys(x^2 for x in -1:0.5:1) == 1:5
@test findall(!iszero, x^2 for x in -1:0.5:1) == [1, 2, 4, 5]
@test argmin(x^2 for x in -1:0.5:1) == 3

# findall return type, see #45495
let gen = (i for i in 1:3);
    @test @inferred(findall(x -> true, gen))::Vector{Int} == [1, 2, 3]
    @test @inferred(findall(x -> false, gen))::Vector{Int} == Int[]
    @test @inferred(findall(x -> x < 0, gen))::Vector{Int} == Int[]
end
let d = Dict()
    d[7]=2
    d[3]=6
    @test @inferred(sort(findall(x -> true, d)))::Vector{Int} == [3, 7]
    @test @inferred(sort(findall(x -> false, d)))::Vector{Any} == []
    @test @inferred(sort(findall(x -> x < 0, d)))::Vector{Any} == []
end

# inference on vararg generator of a type (see #22907 comments)
let f(x) = collect(Base.Generator(=>, x, x))
    @test @inferred(f((1,2))) == [1=>1, 2=>2]
end

# generators with nested loops (#4867)
@test [(i,j) for i=1:3 for j=1:i] == [(1,1), (2,1), (2,2), (3,1), (3,2), (3,3)]

@test [(i,j) for i=1:3 for j=1:i if j>1] == [(2,2), (3,2), (3,3)]

# issue #330
@test [(t=(i,j); i=nothing; t) for i = 1:3 for j = 1:i] ==
    [(1, 1), (2, 1), (2, 2), (3, 1), (3, 2), (3, 3)]

@test map(collect, (((t=(i,j); i=nothing; t) for j = 1:i) for i = 1:3)) ==
    [[(1, 1)],
     [(2, 1), (nothing, 2)],
     [(3, 1), (nothing, 2), (nothing, 3)]]

let a = []
    for x = 1:3, y = 1:3
        push!(a, x)
        x = 0
    end
    @test a == [1,1,1,2,2,2,3,3,3]
end

let i, j
    for outer i = 1:2, j = 1:0
    end
    @test i == 2
    @test !@isdefined(j)
end

# issue #18707
@test [(q,d,n,p) for q = 0:25:100
                 for d = 0:10:100-q
                 for n = 0:5:100-q-d
                 for p = 100-q-d-n
                 if p < n < d < q] == [(50,30,15,5), (50,30,20,0), (50,40,10,0), (75,20,5,0)]

@testset "map/collect return type on generators with $T" for T in (Nothing, Missing)
    x = ["a", "b"]
    res = @inferred collect(s for s in x)
    @test res isa Vector{String}
    res = @inferred map(identity, x)
    @test res isa Vector{String}
    res = @inferred collect(s isa T for s in x)
    @test res isa Vector{Bool}
    res = @inferred map(s -> s isa T, x)
    @test res isa Vector{Bool}
    y = Union{String, T}["a", T()]
    f(s::Union{Nothing, Missing}) = s
    f(s::String) = s == "a"
    res = collect(s for s in y)
    @test res isa Vector{Union{String, T}}
    res = map(identity, y)
    @test res isa Vector{Union{String, T}}
    res = @inferred collect(s isa T for s in y)
    @test res isa Vector{Bool}
    res = @inferred map(s -> s isa T, y)
    @test res isa Vector{Bool}
    res = collect(f(s) for s in y)
    @test res isa Vector{Union{Bool, T}}
    res = map(f, y)
    @test res isa Vector{Union{Bool, T}}
end

@testset "inference of collect with unstable eltype" begin
    @test Core.Compiler.return_type(collect, Tuple{typeof(2x for x in Real[])}) <: Vector
    @test Core.Compiler.return_type(collect, Tuple{typeof(x+y for x in Real[] for y in Real[])}) <: Vector
    @test Core.Compiler.return_type(collect, Tuple{typeof(x+y for x in Real[], y in Real[])}) <: Matrix
    @test Core.Compiler.return_type(collect, Tuple{typeof(x for x in Union{Bool,String}[])}) <: Array
end

let x = rand(2,2)
    (:)(a,b) = x
    @test Float64[ i for i = 1:2 ] == x
    @test Float64[ i+j for i = 1:2, j = 1:2 ] == cat(cat(x[1].+x, x[2].+x; dims=3),
                                                     cat(x[3].+x, x[4].+x; dims=3); dims=4)
end

let (:)(a,b) = (i for i in Base.:(:)(1,10) if i%2==0)
    @test Int8[ i for i = 1:2 ] == [2,4,6,8,10]
end

@testset "Basic tests of Fix1, Fix2, and Fix" begin
    function test_fix1(Fix1=Base.Fix1)
        increment = Fix1(+, 1)
        @test increment(5) == 6
        @test increment(-1) == 0
        @test increment(0) == 1
        @test map(increment, [1, 2, 3]) == [2, 3, 4]

        concat_with_hello = Fix1(*, "Hello ")
        @test concat_with_hello("World!") == "Hello World!"
        # Make sure inference is good:
        @inferred concat_with_hello("World!")

        one_divided_by = Fix1(/, 1)
        @test one_divided_by(10) == 1/10.0
        @test one_divided_by(-5) == 1/-5.0

        return nothing
    end

    function test_fix2(Fix2=Base.Fix2)
        return_second = Fix2((x, y) -> y, 999)
        @test return_second(10) == 999
        @inferred return_second(10)
        @test return_second(-5) == 999

        divide_by_two = Fix2(/, 2)
        @test map(divide_by_two, (2, 4, 6)) == (1.0, 2.0, 3.0)
        @inferred map(divide_by_two, (2, 4, 6))

        concat_with_world = Fix2(*, " World!")
        @test concat_with_world("Hello") == "Hello World!"
        @inferred concat_with_world("Hello World!")

        return nothing
    end

    # Test with normal Base.Fix1 and Base.Fix2
    test_fix1()
    test_fix2()

    # Now, repeat the Fix1 and Fix2 tests, but
    # with a Fix lambda function used in their place
    test_fix1((op, arg) -> Base.Fix{1}(op, arg))
    test_fix2((op, arg) -> Base.Fix{2}(op, arg))

    # Now, we do more complex tests of Fix:
    let Fix=Base.Fix
        @testset "Argument Fixation" begin
            let f = (x, y, z) -> x + y * z
                fixed_f1 = Fix{1}(f, 10)
                @test fixed_f1(2, 3) == 10 + 2 * 3

                fixed_f2 = Fix{2}(f, 5)
                @test fixed_f2(1, 4) == 1 + 5 * 4

                fixed_f3 = Fix{3}(f, 3)
                @test fixed_f3(1, 2) == 1 + 2 * 3
            end
        end
        @testset "Helpful errors" begin
            let g = (x, y) -> x - y
                # Test minimum N
                fixed_g1 = Fix{1}(g, 100)
                @test fixed_g1(40) == 100 - 40

                # Test maximum N
                fixed_g2 = Fix{2}(g, 100)
                @test fixed_g2(150) == 150 - 100

                # One over
                fixed_g3 = Fix{3}(g, 100)
                @test_throws ArgumentError("expected at least 2 arguments to `Fix{3}`, but got 1") fixed_g3(1)
            end
        end
        @testset "Type Stability and Inference" begin
            let h = (x, y) -> x / y
                fixed_h = Fix{2}(h, 2.0)
                @test @inferred(fixed_h(4.0)) == 2.0
            end
        end
        @testset "Interaction with varargs" begin
            vararg_f = (x, y, z...) -> x + 10 * y + sum(z; init=zero(x))
            fixed_vararg_f = Fix{2}(vararg_f, 6)

            # Can call with variable number of arguments:
            @test fixed_vararg_f(1, 2, 3, 4) == 1 + 10 * 6 + sum((2, 3, 4))
            @inferred fixed_vararg_f(1, 2, 3, 4)
            @test fixed_vararg_f(5) == 5 + 10 * 6
            @inferred fixed_vararg_f(5)
        end
        @testset "Errors should propagate normally" begin
            error_f = (x, y) -> sin(x * y)
            fixed_error_f = Fix{2}(error_f, Inf)
            @test_throws DomainError fixed_error_f(10)
        end
        @testset "Chaining Fix together" begin
            f1 = Fix{1}(*, "1")
            f2 = Fix{1}(f1, "2")
            f3 = Fix{1}(f2, "3")
            @test f3() == "123"

            g1 = Fix{2}(*, "1")
            g2 = Fix{2}(g1, "2")
            g3 = Fix{2}(g2, "3")
            @test g3("") == "123"
        end
        @testset "Zero arguments" begin
            f = Fix{1}(x -> x, 'a')
            @test f() == 'a'
        end
        @testset "Dummy-proofing" begin
            @test_throws ArgumentError("expected `N` in `Fix{N}` to be integer greater than 0, but got 0") Fix{0}(>, 1)
            @test_throws ArgumentError("expected type parameter in `Fix` to be `Int`, but got `0.5::Float64`") Fix{0.5}(>, 1)
            @test_throws ArgumentError("expected type parameter in `Fix` to be `Int`, but got `1::UInt64`") Fix{UInt64(1)}(>, 1)
        end
        @testset "Specialize to structs not in `Base`" begin
            struct MyStruct
                x::Int
            end
            f = Fix{1}(MyStruct, 1)
            @test f isa Fix{1,Type{MyStruct},Int}
        end
    end
end
