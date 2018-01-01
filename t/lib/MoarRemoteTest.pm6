use Test;
use MoarVM::Remote;

use nqp;

class DebugTarget {
    has $.proc;
    has $.remote;

    method run($code, &checker, :$start-suspended) {
        my $prefix = nqp::backendconfig<prefix>;

        my $moarbinpath = %*ENV<DEBUGGABLE_MOAR_PATH>.?IO // $prefix.IO.add("bin/moar");

        my $nqplibdir = $prefix.IO.add("share/nqp/lib");
        my $nqpprogpath = $nqplibdir.add("nqp.moarvm");

        my @pre-command  = $moarbinpath.absolute, "--libpath=" ~ $nqplibdir;
        my @post-command = $nqpprogpath, "-e", $code;

        my Supplier $supplier = Supplier::Preserving.new;

        for (1000 ^..^ 65536).pick(*) -> $port {
            my $try-sock = IO::Socket::INET.new(:localhost("localhost"), :localport($port), :listen(True));
            $try-sock.close;

            my $proc = Proc::Async.new(|@pre-command, "--debug-port=$port", |($start-suspended && "--debug-suspend"), |@post-command);

            react {
                whenever $proc.stderr {
                    when / "Address already in use" / {
                        die "Address already in use"
                    }
                    when / "Unknown flag --debug-port=" / {
                        die "MoarVM binary at $moarbinpath doesn't understand debugger flags. Please set the environment variable DEBUGGABLE_MOAR_PATH to a moar binary that does."
                    }
                    last;
                }

                whenever $proc.stdout {
                    $supplier.emit($_);
                }

                whenever $proc.start {
                    $supplier.emit($_);
                    done;
                }

                whenever $proc.ready {
                    whenever MoarVM::Remote.connect($port) -> $client {
                        checker($client, $supplier.Supply);
                        $proc.kill;
                    }
                }
            }
            last;

            CATCH {
                next if $_.Str.contains("Address already in use");
                note $_;
            }
        }
    }
}

