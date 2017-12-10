class X::MoarVM::Remote::ProtocolError is Exception {
    has $.attempted;

    method message {
        "Something went wrong in communicating with the server while trying to $.attempted"
    }
}

class X::MoarVM::Remote::Version is Exception {
    has @.versions;

    method 
}
class MoarVM::Remote {
    has $!sock;

    submethod TWEAK(:$!sock) { }

    method connect(MoarVM::Remote:U: Int $port) {
        start {
            my $sock = IO::Socket::INET.new(:host("localhost"), :port($port));

            my $hello = $sock.recv("MOARVM-REMOTE-DEBUG\0".chars, :bin);
            my $expect = "MOARVM-REMOTE-DEBUG\0".encode("ascii");
            unless $hello.list >>==<< $expect.list {
                $sock.close;
                die X::MoarVM::Remote::ProcolError.new(attempted => "receive the server's handshake message");
            }
            my ($ver1, $ver2) = $sock.recv(2, :bin) xx 2;

            unless all($ver1, $ver2).list >>==<< Buf[uint8].new(0, 1) {
                $sock.close;
                die X::MoarVM::Remote::Pro::
            }

            $sock.write("MOARVM-REMOTE-CLIENT-OK\0".encode("ascii"));

            self.bless(:$sock);
        }
    }
}
