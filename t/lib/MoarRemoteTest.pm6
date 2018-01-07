use v6.d.PREVIEW;

use Test;
use MoarVM::Remote;

use nqp;

class DebugTarget {
    method run($code, &checker, :$start-suspended, :$writable) {
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

            my $proc = Proc::Async.new(|@pre-command, "--debug-port=$port", |("--debug-suspend" if $start-suspended), |@post-command, |%("w" => True if $writable));

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
                        QUIT {
                            note "Checker failed to run";
                            say $_;
                            $proc.kill;
                            die $_;
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

my $testsubject = Q:to/NQP/;
    # allow input
    my sub create_buf($type) {
        my $buf := nqp::newtype(nqp::null(), 'VMArray');
        nqp::composetype($buf, nqp::hash('array', nqp::hash('type', $type)));
        nqp::setmethcache($buf, nqp::hash('new', method () {nqp::create($buf)}));
        $buf;
    };

    my $buf8 := create_buf(uint8);

    # Let's have a lock
    class Lock is repr('ReentrantMutex') { }

    my @locks;

    sub do_thread($lock_number) {
        say("OK R$lock_number");
        nqp::lock(nqp::atpos(@locks, $lock_number));
        say("OK U$lock_number");
    }

    my @threads;

    while 1 {
        my $result := nqp::readfh(nqp::getstdin(), $buf8.new(), 2);
        my $opcode := nqp::chr(nqp::atpos_i($result, 0));
        my $arg := +nqp::chr(nqp::atpos_i($result, 1));
        if $opcode eq "T" { # spawn thread
            nqp::push(@threads, nqp::newthread({ do_thread($arg) }, 0));
            say("OK T$arg");
        } elsif $opcode eq "R" { # run thread
            nqp::threadrun(@threads[$arg]);
        } elsif $opcode eq "L" { # create a locked lock
            my $l := Lock.new;
            nqp::lock($l);
            nqp::bindpos(@locks, $arg, $l);
            say("OK L$arg");
        } elsif $opcode eq "U" { # unlock lock
            nqp::unlock(@locks[$arg]);
        } elsif $opcode eq "J" { # join thread
            nqp::threadjoin(@threads[$arg]);
            say("OK J$arg");
        } elsif $opcode eq "Q" { # quit gracefully
            last;
        } else {
            note("unknown operation requested: $opcode");
            nqp::exit(1);
        }
    }
    say("OK...");
    NQP

my %command_to_letter =
    CreateThread => "T",
    RunThread => "R",
    CreateLock => "L",
    UnlockThread => "U",
    JoinThread => "J",
    Quit => "Q";

sub run_testplan(@plan, $description = "test plan") is export {
    subtest {

    DebugTarget.run: $testsubject, :writable,
    -> $client, $supply, $proc {
        my $outputs =
            $supply.grep({ .key eq "stdout" }).map(*.value).Channel;

        my $reactions = $client.events
                .grep({ .<type> == any(MT_ThreadStarted, MT_ThreadEnded) })
                .Channel;

        for @plan {
            when .key eq "command" {
                my $command = .value ~~ Pair ?? .value.key !! .value;
                my $arg = .value ~~ Pair ?? .value.value !! 0;
                my $to-send = 
                    (%command_to_letter{$command} // fail "command type not understood: $_.value()")
                    ~ $arg;
                lives-ok {
                    await $proc.print: $to-send;
                }, "sent command $command to process";
                if $command ne "Quit" {
                    is-deeply (try await $outputs), "OK $to-send", "command $command executed";
                } else {
                    is-deeply (try await $outputs), "OK...", "quit the program";
                }
            }
            when .key eq "assert" {
                if .value eq "NoEvent" {
                    await Promise.in(0.1);
                    is-deeply $reactions.poll, Nil, "no events received";
                }
                elsif .value eq "NoOutput" {
                    await Promise.in(0.1);
                    is-deeply $outputs.poll, Nil, "no outputs received";
                }
                else {
                    die "Do not understand this assertion: $_.value()";
                }
            }
            when .key eq "receive" {
                die unless .value ~~ Positional;
                subtest {
                    my $received = try await $reactions;
                    cmp-ok $received, "~~", Hash, "an event successfully received";
                    for .value {
                        if .value.VAR.^name eq "Scalar" && not .value.defined {
                            lives-ok {
                                .value = $received{.key};
                            }, "stored result from key $_.key()";
                        } else {
                            cmp-ok $received{.key}, "~~", .value, "check event's $_.key() against $_.value.perl()";
                        }
                    }
                }, "receive an event";
            }
            when .key eq "send" {
                my $commandname = .value.key.head;
                my @params = .value.key.skip;

                my $prom = $client."$commandname"(|@params);

                given .value {
                    if .value.VAR.^name eq "Scalar" && not .value.defined {
                        lives-ok {
                            .value = $prom;
                        }, "stashed away result promise for later";
                    } else {
                        cmp-ok (try await $prom), "~~", .value, "check remote's answer against $_.value.perl()";
                    }
                }
            }
            when .key eq "await" {
                my $prom = .value.key;
                my Mu $checker = .value.value;

                cmp-ok (try await $prom), "~~", .value, "check remote's answer against $_.value.perl()";
            }
            default {
                die "unknown command in test plan: $_.perl()";
            }
        }
    };

    }, $description;
}
