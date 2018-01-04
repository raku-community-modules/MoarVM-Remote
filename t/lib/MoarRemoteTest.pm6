use v6.d.PREVIEW;

use Test;
use MoarVM::Remote;

use nqp;

class DebugTarget {
    method run($code, &checker, :$start-suspended) {
        my $prefix = nqp::backendconfig<prefix>;

        my $moarbinpath = %*ENV<DEBUGGABLE_MOAR_PATH>.?IO // $prefix.IO.add("bin/moar");

        my $nqplibdir = $prefix.IO.add("share/nqp/lib");
        my $nqpprogpath = $nqplibdir.add("nqp.moarvm");

        my @pre-command  = $moarbinpath.absolute, "--libpath=" ~ $nqplibdir.absolute;
        my @post-command = $nqpprogpath.absolute, "-e", $code;

        my $supplier = Supplier::Preserving.new;

        my $conn-refused-retries = 0;

        for (1000 ^..^ 65536).pick(*) -> $port {
            my $try-sock = IO::Socket::INET.new(:localhost("localhost"), :localport($port), :listen(True));
            $try-sock.close;

            my $proc = Proc::Async.new(|@pre-command, "--debug-port=$port", |("--debug-suspend" if $start-suspended), |@post-command);

            react {
                whenever $proc.stderr.lines {
                    when / "Address already in use" / {
                        die "Address already in use"
                    }
                    when / "Unknown flag --debug-port=" / {
                        die "MoarVM binary at $moarbinpath doesn't understand debugger flags. Please set the environment variable DEBUGGABLE_MOAR_PATH to a moar binary that does."
                    }
                    $supplier.emit("stderr" => $_);
                }

                whenever $proc.stdout.lines {
                    $supplier.emit("stdout" => $_);
                }

                whenever $proc.start {
                    if .status === PromiseStatus::Broken {
                        .result.self
                    }
                    $supplier.emit("event" => $_);
                    $supplier.done;
                    last;
                }

                whenever $proc.ready {
                    whenever MoarVM::Remote.connect($port) -> $client {
                        whenever start { checker($client, $supplier.Supply, $proc) } {
                            $proc.kill;
                        }
                    }
                }
            }
            last;

            CATCH {
                next if .Str.contains("Address already in use");
                if .Str.contains("connection refused") && $conn-refused-retries++ < 5 {
                    sleep(0.1);
                    redo;
                }
            }
            $conn-refused-retries = 0;
        }
    }
}

