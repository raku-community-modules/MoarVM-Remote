use Test;
use MoarVM::Remote;

use nqp;

class DebugTarget {
    has $.proc;
    has $.remote;

    method run($code, :$start-suspended) {
        my $prefix = nqp::backendconfig<prefix>;
        my $moarbinpath = $prefix.IO.add("bin/moar");
        my $nqplibdir = $prefix.IO.add("share/nqp/lib");
        my $nqpprogpath = $nqplibdir.add("nqp.moarvm");

        my @pre-command  = $moarbindir.absolute, "--libpath=" ~ $nqplibdir;
        my @post-command = $nqpprogpath, "-e", $code;

        for (1000 ^..^ 65536).pick(*) -> $port {
            my $try-sock = IO::Socket::INET.new(:localhost("localhost"), :localport(9999), :listen(True));
            $try-sock.close;

            my @command = |
            my $proc = Proc::Async.new(|@pre-command, "--debug-port=$port", |($start-suspended && "--debug-suspend"), |@post-command);

            # TODO check for panic (a race to use the address or moarvm without debug support)
            # TODO create object and return it

            CATCH {
                next if $!.Str.contains("Address already in use");
            }
        }
    }
}

