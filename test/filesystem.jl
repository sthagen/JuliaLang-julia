# This file is a part of Julia. License is MIT: https://julialang.org/license

mktempdir() do dir

    # Create test file
    filename = joinpath(dir, "file.txt")
    text = "123456"
    write(filename, text)

    # test filesystem truncate (shorten)
    file = Base.Filesystem.open(filename, Base.Filesystem.JL_O_RDWR)
    Base.Filesystem.truncate(file, 2)
    text = text[1:2]
    @test length(read(file)) == 2
    close(file)

    # test filesystem truncate (lengthen)
    file = Base.Filesystem.open(filename, Base.Filesystem.JL_O_RDWR)
    Base.Filesystem.truncate(file, 20)
    @test length(read(file)) == 20
    close(file)

    # test filesystem futime
    file = Base.Filesystem.open(filename, Base.Filesystem.JL_O_RDWR)
    Base.Filesystem.futime(file, 1.0, 2.0)
    @test Base.Filesystem.stat(file).mtime == 2.0
    close(file)

    # test filesystem readbytes!
    file = Base.Filesystem.open(filename, Base.Filesystem.JL_O_RDWR)
    res = ones(UInt8, 80)
    Base.Filesystem.readbytes!(file, res)
    @test res == UInt8[text..., (i > 20 for i in (length(text) + 1):length(res))...]
    close(file)

end

import Base.Filesystem: S_IRUSR, S_IRGRP, S_IROTH
@testset "types of permission mask constants" begin
    @test S_IRUSR & ~S_IRGRP == S_IRUSR
    @test typeof(S_IRUSR) == typeof(S_IRGRP) == typeof(S_IROTH)
end

@testset "Base.Filesystem docstrings" begin
    undoc = Docs.undocumented_names(Base.Filesystem)
    @test_broken isempty(undoc)
    @test undoc == [:File, :Filesystem, :cptree, :futime, :sendfile, :unlink]
end

@testset "write return type" begin
    @test Base.return_types(write, (Base.Filesystem.File, UInt8)) == [Int]
end
