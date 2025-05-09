# This file is a part of Julia. License is MIT: https://julialang.org/license

using Sockets, Random, Test
using Base: Experimental

# set up a watchdog alarm for 10 minutes
# so that we can attempt to get a "friendly" backtrace if something gets stuck
# (although this'll also terminate any attempted debugging session)
# expected test duration is about 5-10 seconds
function killjob(d)
    Core.print(Core.stderr, d)
    if Sys.islinux()
        SIGINFO = 10
    elseif Sys.isbsd()
        SIGINFO = 29
    end
    if @isdefined(SIGINFO)
        ccall(:uv_kill, Cint, (Cint, Cint), getpid(), SIGINFO)
        sleep(5) # Allow time for profile to collect and print before killing
    end
    ccall(:uv_kill, Cint, (Cint, Cint), getpid(), Base.SIGTERM)
    nothing
end
sockets_watchdog_timer = Timer(t -> killjob("KILLING BY SOCKETS TEST WATCHDOG\n"), 600)

@testset "parsing" begin
    @test ip"127.0.0.1" == IPv4(127,0,0,1)
    @test ip"192.0" == IPv4(192,0,0,0)

    # These used to work, but are now disallowed. Check that they error
    @test_throws ArgumentError parse(IPv4, "192.0xFFF") # IPv4(192,0,15,255)
    @test_throws ArgumentError parse(IPv4, "192.0xFFFF") # IPv4(192,0,255,255)
    @test_throws ArgumentError parse(IPv4, "192.0xFFFFF") # IPv4(192,15,255,255)
    @test_throws ArgumentError parse(IPv4, "192.0xFFFFFF") # IPv4(192,255,255,255)
    @test_throws ArgumentError parse(IPv4, "022.0.0.1") # IPv4(18,0,0,1)

    @test UInt(IPv4(0x01020304)) == 0x01020304
    @test Int(IPv4("1.2.3.4")) == Int(0x01020304) == Int32(0x01020304)
    @test Int128(IPv6("2001:1::2")) == 42540488241204005274814694018844196866
    @test_throws InexactError Int16(IPv4("1.2.3.4"))
    @test_throws InexactError Int64(IPv6("2001:1::2"))

    let ipv = parse(IPAddr, "127.0.0.1")
        @test isa(ipv, IPv4)
        @test ipv == ip"127.0.0.1"
        @test sprint(show, ipv) == "ip\"127.0.0.1\""
    end

    @test_throws ArgumentError parse(IPv4, "192.0xFFFFFFF")
    @test_throws ArgumentError IPv4(192,255,255,-1)
    @test_throws ArgumentError IPv4(192,255,255,256)

    @test_throws ArgumentError parse(IPv4, "192.0xFFFFFFFFF")
    @test_throws ArgumentError parse(IPv4, "192.")
    @test_throws ArgumentError parse(IPv4, "256.256.256.256")
    # too many fields
    @test_throws ArgumentError parse(IPv6, "256:256:256:256:256:256:256:256:256:256:256:256")

    @test_throws ArgumentError IPv4(-1)
    @test_throws ArgumentError IPv4(typemax(UInt32) + Int64(1))

    @test ip"::1" == IPv6(1)
    @test ip"2605:2700:0:3::4713:93e3" == IPv6(parse(UInt128,"260527000000000300000000471393e3", base = 16))

    @test ip"2001:db8:0:0:0:0:2:1" == ip"2001:db8::2:1" == ip"2001:db8::0:2:1"

    @test ip"0:0:0:0:0:ffff:127.0.0.1" == IPv6(0xffff7f000001)

    let ipv = parse(IPAddr, "0:0:0:0:0:ffff:127.0.0.1")
        @test isa(ipv, IPv6)
        @test ipv == ip"0:0:0:0:0:ffff:127.0.0.1"
    end

    @test_throws ArgumentError IPv6(-1)
    @test_throws ArgumentError IPv6(1,1,1,1,1,1,1,-1)
    @test_throws ArgumentError IPv6(1,1,1,1,1,1,1,typemax(UInt16)+1)

    @test IPv6(UInt16(1), UInt16(1), UInt16(1), UInt16(1), UInt16(1), UInt16(1), UInt16(1), UInt16(1)) == IPv6(1,1,1,1,1,1,1,1)

    @test_throws BoundsError Sockets.ipv6_field(IPv6(0xffff7f000001), -1)
    @test_throws BoundsError Sockets.ipv6_field(IPv6(0xffff7f000001), 9)
end

@testset "InetAddr constructor" begin
    inet = Sockets.InetAddr(IPv4(127,0,0,1), 1024)
    @test inet.host == ip"127.0.0.1"
    @test inet.port == 1024
    str = "Sockets.InetAddr{$(isdefined(Main, :IPv4) ? "" : "Sockets.")IPv4}(ip\"127.0.0.1\", 1024)"
    @test sprint(show, inet) == str
    inet = Sockets.InetAddr("127.0.0.1", 1024)
    @test inet.host == ip"127.0.0.1"
    @test inet.port == 1024
end
@testset "InetAddr invalid port" begin
    @test_throws InexactError Sockets.InetAddr(IPv4(127,0,0,1), -1)
    @test_throws InexactError Sockets.InetAddr(IPv4(127,0,0,1), typemax(UInt16)+1)
end

@testset "isless and comparisons" begin
    @test ip"1.2.3.4" < ip"1.2.3.7" < ip"2.3.4.5"
    @test ip"1.2.3.4" >= ip"1.2.3.4" >= ip"1.2.3.1"
    @test isless(ip"1.2.3.4", ip"1.2.3.5")
    @test_throws MethodError sort([ip"2.3.4.5", ip"1.2.3.4", ip"2001:1:2::1"])
end

@testset "broadcastable" begin
    @test size(ip"127.0.0.1" .== ip"127.0.0.1") == ()
    @test size(ip"::1" .== ip"::1") == ()
end

@testset "RFC 5952 Compliance" begin
    @test repr(ip"2001:db8:0:0:0:0:2:1") == "ip\"2001:db8::2:1\""
    @test repr(ip"2001:0db8::0001") == "ip\"2001:db8::1\""
    @test repr(ip"2001:db8::1:1:1:1:1") == "ip\"2001:db8:0:1:1:1:1:1\""
    @test repr(ip"2001:db8:0:0:1:0:0:1") == "ip\"2001:db8::1:0:0:1\""
    @test repr(ip"2001:0:0:1:0:0:0:1") == "ip\"2001:0:0:1::1\""
end

defaultport = rand(2000:4000)
@testset "writing to/reading from a socket, getsockname and getpeername" begin
    for testport in [0, defaultport]
        port = Channel(1)
        tsk = @async begin
            local (p, s) = listenany(testport)
            @test p != 0
            @test getsockname(s) == (Sockets.localhost, p)
            put!(port, p)
            for i in 1:3
                sock = accept(s)
                @test getsockname(sock) == (Sockets.localhost, p)
                let peer = getpeername(sock)::Tuple{IPAddr, UInt16}
                    @test peer[1] == Sockets.localhost
                    @test 0 != peer[2] != p
                end
                # test write call
                write(sock, "Hello World\n")

                # test "locked" println to a socket
                Experimental.@sync begin
                    for i in 1:100
                        @async println(sock, "a", 1)
                    end
                end
                close(sock)
            end
            close(s)
        end
        wait(port)
        let p = fetch(port)
            otherip = getipaddr()
            if otherip != Sockets.localhost
                @test_throws Base._UVError("connect", Base.UV_ECONNREFUSED) connect(otherip, p)
            end
            for i in 1:3
                client = connect(p)
                let name = getsockname(client)::Tuple{IPAddr, UInt16}
                    @test name[1] == Sockets.localhost
                    @test 0 != name[2] != p
                end
                @test getpeername(client) == (Sockets.localhost, p)
                @test read(client, String) == "Hello World\n" * ("a1\n"^100)
            end
        end
        wait(tsk)
    end

    mktempdir() do tmpdir
        socketname = Sys.iswindows() ? ("\\\\.\\pipe\\uv-test-" * randstring(6)) : joinpath(tmpdir, "socket")
        local nconn = 0
        srv = listen(socketname)
        t = accept(srv) do client
            write(client, "Hello World $(nconn += 1)\n")
            close(client)
            nconn == 3 && Base.wait_close(srv)
        end
        @test read(connect(socketname), String) == "Hello World 1\n"
        @test read(connect(socketname), String) == "Hello World 2\n"
        @test read(connect(socketname), String) == "Hello World 3\n"
        conn = connect(socketname)
        close(srv)
        wait(t)
        @test read(conn, String) == ""
    end
end

@testset "getsockname errors" begin
    sock = TCPSocket()
    serv = Sockets.TCPServer()
    @test_throws MethodError getpeername(serv)
    @test_throws Base._UVError("cannot obtain socket name", Base.UV_EBADF) getpeername(sock)
    @test_throws Base._UVError("cannot obtain socket name", Base.UV_EBADF) getsockname(serv)
    @test_throws Base._UVError("cannot obtain socket name", Base.UV_EBADF) getsockname(sock)
    close(sock)
    close(serv)
end


@testset "getnameinfo on some unroutable IP addresses (RFC 5737)" begin
    try
        getnameinfo(ip"192.0.2.1")
        getnameinfo(ip"198.51.100.1")
        getnameinfo(ip"203.0.113.1")
        getnameinfo(ip"0.1.1.1")
        getnameinfo(ip"::ffff:0.1.1.1")
        getnameinfo(ip"::ffff:192.0.2.1")
        getnameinfo(ip"2001:db8::1")
    catch
        # NOTE: Default Ubuntu installations contain a faulty DNS configuration
        # that returns `EAI_AGAIN` instead of `EAI_NONAME`.  To fix this, try
        # installing `libnss-resolve`, which installs the `systemd-resolve`
        # backend for NSS, which should fix it.
        #
        # If you are running tests inside Docker, you'll need to install
        # `libnss-resolve` both outside Docker (i.e. on the host machine) and
        # inside the Docker container.
        if Sys.islinux()
            error_msg = string(
                "`getnameinfo` failed on an unroutable IP address. ",
                "If your DNS setup seems to be working, try installing libnss-resolve",
            )
            @error(error_msg)
        end
    end
    @test getnameinfo(ip"192.0.2.1") == "192.0.2.1"
    @test getnameinfo(ip"198.51.100.1") == "198.51.100.1"
    # Temporarily broken due to a DNS issue. See https://github.com/JuliaLang/julia/issues/55008
    @test_skip getnameinfo(ip"203.0.113.1") == "203.0.113.1"
    @test getnameinfo(ip"0.1.1.1") == "0.1.1.1"
    @test getnameinfo(ip"::ffff:0.1.1.1") == "::ffff:0.1.1.1"
    @test getnameinfo(ip"::ffff:192.0.2.1") == "::ffff:192.0.2.1"
    @test getnameinfo(ip"2001:db8::1") == "2001:db8::1"
end

@testset "getnameinfo on some valid IP addresses" begin
    @test !isempty(getnameinfo(ip"::")::String)
    @test !isempty(getnameinfo(ip"0.0.0.0")::String)
    @test !isempty(getnameinfo(ip"10.1.0.0")::String)
    @test !isempty(getnameinfo(ip"10.1.0.255")::String)
    @test !isempty(getnameinfo(ip"10.1.255.1")::String)
    @test !isempty(getnameinfo(ip"255.255.255.255")::String)
    @test !isempty(getnameinfo(ip"255.255.255.0")::String)
    @test !isempty(getnameinfo(ip"192.168.0.1")::String)
    @test !isempty(getnameinfo(ip"::1")::String)
end

@testset "getaddrinfo" begin
    @test getaddrinfo("127.0.0.1") == ip"127.0.0.1"
    @test getaddrinfo("::1") == ip"::1"
    let localhost = getnameinfo(ip"127.0.0.1")::String
        @test !isempty(localhost) && localhost != "127.0.0.1"
        @test !isempty(getalladdrinfo(localhost)::Vector{IPAddr})
        @test getaddrinfo(localhost, IPv4)::IPv4 != ip"0.0.0.0"
        @test try
            getaddrinfo(localhost, IPv6)::IPv6 != ip"::"
        catch ex
            isa(ex, Sockets.DNSError) && ex.code == Base.UV_EAI_NONAME && ex.host == localhost
        end
    end
    @test_throws Sockets.DNSError getaddrinfo(".invalid")
    @test_throws ArgumentError getaddrinfo("localhost\0") # issue #10994
    @test_throws Base._UVError("connect", Base.UV_ECONNREFUSED) connect(ip"127.0.0.1", 21452)
    e = (try; getaddrinfo(".invalid"); catch ex; ex; end)
    @test startswith(sprint(show, e), "DNSError:")
end

@testset "invalid port" begin
    @test_throws ArgumentError connect(ip"127.0.0.1", -1)
    @test_throws ArgumentError connect(ip"127.0.0.1", typemax(UInt16)+1)
    @test_throws ArgumentError connect(ip"0:0:0:0:0:ffff:127.0.0.1", -1)
    @test_throws ArgumentError connect(ip"0:0:0:0:0:ffff:127.0.0.1", typemax(UInt16)+1)
end

@testset "put! in listenany(defaultport)" begin
    (p, server) = listenany(defaultport)
    r = Channel(1)
    tsk = @async begin
        put!(r, :start)
        @test_throws Base._UVError("accept", Base.UV_ECONNABORTED) accept(server)
    end
    @test fetch(r) === :start
    close(server)
    wait(tsk)
end

# test connecting to a named port
let localhost = ip"127.0.0.1"
    global randport
    randport, server = listenany(localhost, defaultport)
    @async connect(localhost, randport)
    s1 = accept(server)
    @test_throws ErrorException("client TCPSocket is not in initialization state") accept(server, s1)
    @test_throws Base._UVError("listen", Base.UV_EADDRINUSE) listen(randport)
    port2, server2 = listenany(localhost, randport)
    @test randport != port2
    close(server)
    close(server2)
end

@test_throws Sockets.DNSError connect(".invalid", 80)

@testset "UDPSocket" begin
    # test show() function for UDPSocket()
    @test repr(UDPSocket()) ∈ ("Sockets.UDPSocket(init)", "UDPSocket(init)")

    let
        a = UDPSocket()
        b = UDPSocket()
        bind(a, ip"127.0.0.1", randport)
        bind(b, ip"127.0.0.1", randport + 1)

        Experimental.@sync begin
            let i = 0
                for _ = 1:30
                    @async let msg = String(recv(a))
                        @test msg == "Hello World $(i += 1)"
                    end
                end
            end
            yield()
            for i = 1:30
                send(b, ip"127.0.0.1", randport, "Hello World $i")
            end
        end
        let msg = Vector{UInt8}("fedcba9876543210"^36) # The minimum reassembly buffer size for IPv4 is 576 bytes
            tsk = @async @test recv(a) == msg
            @test send(b, ip"127.0.0.1", randport, msg) === nothing
            wait(tsk)
        end
        let msg = Vector{UInt8}("1234"^16377) # The maximum size of an IPv4 datagram is 65535 bytes, including the header
            @test_throws(Base._UVError("send", Base.UV_EMSGSIZE),
                         send(b, ip"127.0.0.1", randport, msg))
            pop!(msg)
            tsk = @async recv(a)
            try
                send(b, ip"127.0.0.1", randport, msg)
            catch ex
                if !(ex isa Base.IOError && ex.code == Base.UV_EMSGSIZE) || Sys.islinux() || Sys.iswindows()
                    # this is allowed failure on some platforms which might further restrict
                    # the maximum packet size being sent (even locally), such as BSD's `sysctl net.inet.udp.maxdgram`
                    rethrow()
                end
                empty!(msg)
                send(b, ip"127.0.0.1", randport, msg) # check that the socket is still alive
            end
            @test fetch(tsk) == msg
        end
        let tsk = @async send(b, ip"127.0.0.1", randport, "WORLD HELLO")
            (inetaddr, data) = recvfrom(a)
            @test inetaddr.host == ip"127.0.0.1" && String(data) == "WORLD HELLO"
            wait(tsk)
        end
        close(a)
        close(b)
    end

    @test_throws MethodError bind(UDPSocket(), randport)

    let
        a = UDPSocket()
        b = UDPSocket()
        bind(a, ip"::1", UInt16(randport))
        bind(b, ip"::1", UInt16(randport + 1))

        for i = 1:3
            tsk = @async begin
                let (inetaddr, data) = recvfrom(a)
                    @test inetaddr.host == ip"::1"
                    @test String(data) == "Hello World"
                end
            end
            send(b, ip"::1", randport, "Hello World")
            wait(tsk)
        end
    end
end

@testset "local ports" begin
    for (addr, porthint) in [
            (IPv4("127.0.0.1"), UInt16(11011)),
            (IPv6("::1"), UInt16(11012)),
            (getipaddr(), UInt16(11013)) ]
        port, listen_sock = listenany(addr, porthint)
        gsn_addr, gsn_port = getsockname(listen_sock)

        @test addr == gsn_addr
        @test port == gsn_port

        # connect to it
        client_sock = connect(addr, port)
        test_done = false
        Experimental.@sync begin
            @async begin
                Base.wait_readnb(client_sock, 1)
                test_done || error("Client disconnected prematurely.")
            end
            @async begin
                server_sock = accept(listen_sock)

                self_client_addr, self_client_port = getsockname(client_sock)
                peer_client_addr, peer_client_port = getpeername(client_sock)
                self_srvr_addr, self_srvr_port = getsockname(server_sock)
                peer_srvr_addr, peer_srvr_port = getpeername(server_sock)

                @test self_client_addr == peer_client_addr == self_srvr_addr == peer_srvr_addr

                @test peer_client_port == self_srvr_port
                @test peer_srvr_port == self_client_port
                @test self_srvr_port != self_client_port

                test_done = true

                close(listen_sock)
                close(client_sock)
                close(server_sock)
            end
        end
    end
end

@testset "Local-machine broadcast" begin
    let a, b, c
        # Apple does not support broadcasting on 127.255.255.255
        bcastdst = Sys.isapple() ? ip"255.255.255.255" : ip"127.255.255.255"

        function create_socket(addr::IPAddr, port)
            s = UDPSocket()
            bind(s, addr, port, reuseaddr = true, enable_broadcast = true)
            return s
        end

        # Wait for futures to finish with a given timeout
        function wait_with_timeout(recvs, TIMEOUT_VAL = 3*1e9)
            t0 = time_ns()
            recvs_check = copy(recvs)
            while ((length(filter!(t->!istaskdone(t), recvs_check)) > 0)
                  && (time_ns() - t0 < TIMEOUT_VAL))
                sleep(0.05)
            end
            length(recvs_check) > 0 && error("timeout")
            map(wait, recvs)
        end

        # First, test IPv4 broadcast
        port = 2000
        a, b, c = [create_socket(ip"0.0.0.0", port) for i in 1:3]
        try
            # bsd family do not allow broadcasting on loopbacks
            @static if !Sys.isbsd() || Sys.isapple()
                send(c, bcastdst, port, "hello")
                recvs = [@async @test String(recv(s)) == "hello" for s in (a, b)]
                wait_with_timeout(recvs)
            end
        catch e
            if isa(e, Base.IOError) && Base.uverrorname(e.code) == "EPERM"
                @warn "UDP IPv4 broadcast test skipped (permission denied upon send, restrictive firewall?)"
            elseif Sys.isapple() && isa(e, Base.IOError) && Base.uverrorname(e.code) == "EHOSTUNREACH"
                @warn "UDP IPv4 broadcast test skipped (local network access not granted?)"
            else
                rethrow()
            end
        end
        [close(s) for s in [a, b, c]]

        # Test ipv6 broadcast groups
        a, b, c = [create_socket(ip"::", port) for i in 1:3]
        try
            # Exemplary Interface-local ipv6 multicast group, if we wanted this to actually be routed
            # to other computers, we should use a link-local or larger address scope group
            # bsd family and darwin do not allow broadcasting on loopbacks
            @static if !Sys.isbsd() && !Sys.isapple()
                group = ip"ff11::6a75:6c69:61"
                join_multicast_group(a, group)
                join_multicast_group(b, group)

                send(c, group, port, "hello")
                recvs = [@async @test String(recv(s)) == "hello" for s in (a, b)]
                wait_with_timeout(recvs)

                leave_multicast_group(a, group)
                leave_multicast_group(b, group)

                send(c, group, port, "hello")
                recvs = [@async @test String(recv(s)) == "hello" for s in (a, b)]
                # We only wait 200ms since we're pretty sure this is going to time out
                @test_throws ErrorException wait_with_timeout(recvs, 2e8)
            end
        catch e
            if isa(e, Base.IOError) && Base.uverrorname(e.code) == "EPERM"
                @warn "UDP IPv6 broadcast test skipped (permission denied upon send, restrictive firewall?)"
            else
                rethrow()
            end
        end
    end
end

@testset "Pipe" begin
    P = Pipe()
    Base.link_pipe!(P)
    write(P, "hello")
    @test bytesavailable(P) == 0
    @test !eof(P)
    @test read(P, Char) === 'h'
    @test !eof(P)
    @test read(P, Char) === 'e'
    @test isopen(P)
    t = @async begin
        # feed uv_read one more event so that it triggers the transition from active -> open
        write(P, "w")
        while P.out.status != Base.StatusOpen
            yield() # wait for that transition
        end
        close(P.in)
    end
    # on unix, this proves that the kernel can buffer a single byte
    # even with no registered active call to read
    # on windows, the kernel fails to do even that
    # causing the `write` call to freeze
    # so we end up forced to do a slightly weaker test here
    Sys.iswindows() || wait(t)
    @test isopen(P) # without an active uv_reader, P shouldn't be closed yet
    @test !eof(P) # should already know this,
    @test isopen(P) #  so it still shouldn't have an active uv_reader
    @test readuntil(P, 'w') == "llo"
    Sys.iswindows() && wait(t)
    @test eof(P)
    @test !isopen(P) # eof test should have closed this by now
    close(P) # should be a no-op, just make sure
    @test !isopen(P)
    @test eof(P)
end

@testset "connect!" begin
    # test the method matching connect!(::TCPSocket, ::Sockets.InetAddr{T<:Base.IPAddr})
    let addr = Sockets.InetAddr(ip"127.0.0.1", 4444)
        srv = listen(addr)
        r = @async close(accept(srv))
        close(connect(addr))
        fetch(r)
        close(srv)
    end

    let addr = Sockets.InetAddr(ip"127.0.0.1", 4444)
        srv = listen(addr)
        r = @async close(srv)
        @test_throws Base._UVError("accept", Base.UV_ECONNABORTED) accept(srv)
        fetch(r)
    end

    let addr = Sockets.InetAddr(ip"192.0.2.5", 4444)
        s = Sockets.TCPSocket()
        Sockets.connect!(s, addr)
        r = @async close(s)
        @test_throws Base._UVError("connect", Base.UV_ECANCELED) Sockets.wait_connected(s)
        fetch(r)
    end
end

@testset "iswritable" begin
    let addr = Sockets.InetAddr(ip"127.0.0.1", 4445)
        srv = listen(addr)
        let s = Sockets.TCPSocket()
            Sockets.connect!(s, addr)
            @test iswritable(s) broken=Sys.iswindows()
            close(s)
            @test !iswritable(s)
        end
        let s = Sockets.connect(addr)
            @test iswritable(s)
            closewrite(s)
            @test !iswritable(s)
            close(s)
        end
        close(srv)
        srv = listen(addr)
        let s = Sockets.connect(addr)
            let c = accept(srv)
                Base.errormonitor(@async try; write(c, c); finally; close(c); end)
            end
            @test iswritable(s)
            write(s, "hello world\n")
            closewrite(s)
            @test !iswritable(s)
            @test isreadable(s)
            @test read(s, String) == "hello world\n"
            @test !isreadable(s)
            @test !isopen(s)
            close(s)
        end
        close(srv)
    end
end

@testset "TCPSocket RawFD constructor" begin
    if Sys.islinux()
        let fd = ccall(:socket, Int32, (Int32, Int32, Int32),
                       2, # AF_INET
                       1, # SOCK_STREAM
                       0)
            s = Sockets.TCPSocket(RawFD(fd))
            close(s)
        end
    end
end

@testset "fd() methods" begin
    function valid_fd(x)
        if Sys.iswindows()
            return x isa Base.OS_HANDLE
        elseif !Sys.iswindows()
            value = Base.cconvert(Cint, x)

            # 2048 is a bit arbitrary, it depends on the process not having too many
            # file descriptors open. But select() has a limit of 1024 and people
            # don't seem to hit it too often so let's hope twice that is safe.
            return value > 0 && value < 2048
        end
    end

    sock = TCPSocket(; delay=false)
    @test valid_fd(fd(sock))

    sock = UDPSocket()
    bind(sock, Sockets.localhost, 0)
    @test valid_fd(fd(sock))

    server = listen(Sockets.localhost, 0)
    @test valid_fd(fd(server))
end

@testset "TCPServer constructor" begin
    s = Sockets.TCPServer(; delay=false)
    if ccall(:jl_has_so_reuseport, Int32, ()) == 1
        @test 0 == ccall(:jl_tcp_reuseport, Int32, (Ptr{Cvoid},), s.handle)
    end
end

@testset "getipaddrs" begin
    @test getipaddr() in getipaddrs()

    has_ipv4 = !isempty(getipaddrs(IPv4))
    if has_ipv4
        @test getipaddr(IPv4) in getipaddrs(IPv4)
    else
        @test_throws "No networking interface available" getipaddr(IPv4)
    end

    has_ipv6 = !isempty(getipaddrs(IPv6))
    if has_ipv6
        @test getipaddr(IPv6) in getipaddrs(IPv6)
    else
        @test_throws "No networking interface available" getipaddr(IPv6)
    end

    @testset "getipaddr() prefers IPv4 over IPv6" begin
        if has_ipv4
            @test getipaddr() isa IPv4
        else
            @test getipaddr() isa IPv6
        end
    end

    @testset "including loopback addresses" begin
        @test issubset(getipaddrs(), getipaddrs(loopback=true))
        @test issubset(getipaddrs(IPv6), getipaddrs(IPv6, loopback=true))
    end
end

@testset "address scope" begin
    @test islinklocaladdr(ip"169.254.1.0")
    @test islinklocaladdr(ip"169.254.254.255")
    @test islinklocaladdr(ip"fe80::")
    @test islinklocaladdr(ip"febf::")
    @test !islinklocaladdr(ip"127.0.0.1")
    @test !islinklocaladdr(ip"2001::")

end

@static if !Sys.iswindows()
    # Issue #29234
    @testset "TCPSocket stdin" begin
        let addr = Sockets.InetAddr(ip"127.0.0.1", 4455)
            srv = listen(addr)
            s = connect(addr)

            @test success(pipeline(`$(Base.julia_cmd()) --startup-file=no -e "exit()" -i`, stdin=s))

            close(s)
            close(srv)
        end
    end
end

# Issues #18818 and #24169
mutable struct RLimit
    cur::Int64
    max::Int64
end
function with_ulimit(f::Function, stacksize::Int)
    RLIMIT_STACK = 3 # from /usr/include/sys/resource.h
    rlim = Ref(RLimit(0, 0))
    # Get the current maximum stack size in bytes
    rc = ccall(:getrlimit, Cint, (Cint, Ref{RLimit}), RLIMIT_STACK, rlim)
    @assert rc == 0
    current = rlim[].cur
    try
        rlim[].cur = stacksize * 1024
        ccall(:setrlimit, Cint, (Cint, Ref{RLimit}), RLIMIT_STACK, rlim)
        f()
    finally
        rlim[].cur = current
        ccall(:setrlimit, Cint, (Cint, Ref{RLimit}), RLIMIT_STACK, rlim)
    end
    nothing
end
@static if Sys.isapple()
    @testset "Issues #18818 and #24169" begin
        with_ulimit(7001) do
            @test getaddrinfo("localhost") isa IPAddr
        end
    end
end


close(sockets_watchdog_timer)

@testset "Docstrings" begin
    @test isempty(Docs.undocumented_names(Sockets))
end
