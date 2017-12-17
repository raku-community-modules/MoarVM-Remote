constant REQ_SUSPEND    = 1;
constant REQ_RESUME     = 2;
constant REQ_THREADLIST = 3;
constant REQ_DUMP       = 9;

class X::MoarVM::Remote::ProtocolError is Exception {
    has $.attempted;

    method message {
        "Something went wrong in communicating with the server while trying to $.attempted"
    }
}

class X::MoarVM::Remote::Version is Exception {
    has @.versions;

    method message {
        "Incompatible remote version: @.versions[]"
    }
}

sub recv32be($sock) {
    my $buf = $sock.recv(4, :bin);
    return [+] $buf.list >>+<>> (24, 16, 8, 0);
}
sub send32be($sock, $num) {
    my $buf = Buf[uint8].new($num.polymod(255, 255, 255, 255)[^4].reverse);
    $sock.write($buf);
}

class MoarVM::Remote {
    has $!sock;
    has $!worker;

    has Lock $!queue-lock;
    has @!request-promises;

    has Lock $!id-lock;
    has int32 $!req_id;

    submethod TWEAK(:$!sock) {
        $!queue-lock .= new;
        $!id-lock .= new;
        $!req_id = 1;
    }

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

            unless all($ver1, $ver2).list >>==<< (0, 1) {
                $sock.close;
                die X::MoarVM::Remote::Pro::
            }

            $sock.write("MOARVM-REMOTE-CLIENT-OK\0".encode("ascii"));

            my $res = self.bless(:$sock);
            $res!worker;
            $res
        }
    }

    method !worker {
        $!worker //= start {
            note "waiting for data to come in";
            my $id = recv32be($!sock);
            note "worker received response for $id";
            my $task;
            $!queue-lock.protect: {
                $task = @!request-promises.grep(*.key == $id).head.value;
                @!request-promises .= grep(*.key != $id);
            }
            my $command = $!sock.read(1, :bin)[0];
            note "its command is $command";
            if $command == 0 {
                $task.break($command)
            } else {
                $task.keep($command)
            }
            await $task.promise;
        }
    }

    method !get-request-id {
        $!id-lock.protect: {
            my $res = $!req_id;
            $!req_id += 2;
            $res
        }
    }

    method !send-request($type, $data) {
        note "will send request";
        my $id = self!get-request-id;
        note "will have id $id";
        send32be($!sock, $id);

        note "will send type";
        $!sock.write(Buf[uint8].new($type));
        note "type sent";

        given $data {
            when Int {
                send32be($!sock, $_)
            }
            when Buf {
                $!sock.write($data);
            }
            default {
                note "didn't send data";
            }
        }

        note "sending request";

        my $prom = Promise.new;
        $!queue-lock.protect: {
            @!request-promises.push($id => $prom.vow);
        }
        note "queued";
        $prom;
    }

    method threads-list {
        self!send-request(3, Nil).then({
            .result;
            die unless $!sock.recv(4, :bin).list >>==<< [0x54, 0x48, 0x4c, 0];
            my $threadcount = $!sock.&recv32be;
            say "got $threadcount threads";
            do for ^$threadcount {
                my $id = $!sock.&recv32be;
                my $stage = $!sock.&recv32be;
                my $gc_status = $!sock.&recv32be;
                my $app_lifetime = $!sock.&recv32be;

                say "$id";
                say "$stage $gc_status $app_lifetime";
                [$id, $stage, $gc_status, $app_lifetime]
            }
        })
    }

    method suspend(Int $id) {
        self!send-request(1, $id).then({
            .result;
            recv32be($!sock);
        })
    }

    method resume(Int $id) {
        self!send-request(2, $id).then({
            .result;
            recv32be($!sock);
        })
    }
    method dump(Int $id) {
        self!send-request(9, $id).then({
            .result;
            recv32be($!sock);
        })
    }
}
