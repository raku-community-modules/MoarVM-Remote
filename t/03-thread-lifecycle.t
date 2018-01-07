use v6.d.PREVIEW;

use lib $?FILE.IO.sibling("lib");

use Test;

use MoarVM::Remote;
use MoarRemoteTest;

plan 12;

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

Promise.in(10).then: { note "Did not finish test in 10 seconds. Considering this a failure."; exit 1 }

DebugTarget.run($testsubject, :writable,
    -> $client, $supply, $proc {
        my $outputs =
            $supply.grep({ .key eq "stdout" }).map(*.value).Channel;

        my $reactions = $client.events
                .grep({ .<type> == any(MT_ThreadStarted, MT_ThreadEnded) })
                .Channel;

        await $proc.print("L0");
        is-deeply $outputs.receive, "OK L0", "lock created ok";
        await $proc.print("T0");
        is-deeply $outputs.receive, "OK T0", "thread created ok";
        sleep 0.1;
        is-deeply $reactions.poll, Nil, "thread creation message not sent yet";
        await $proc.print("R0");
        is-deeply $outputs.receive, "OK R0", "ran thread 0";
        cmp-ok $reactions.receive, "~~",
            all([type => *, id => *, thread => *, app_lifetime => 0]),
            "running thread sends a thread started message";
        sleep 0.1;
        is-deeply $reactions.poll, Nil, "no more messages";
        is-deeply $outputs.poll, Nil, "no more outputs";

        await $proc.print("U0");
        is-deeply $outputs.receive, "OK U0", "unlocked thread 0";
        cmp-ok $reactions.receive, "~~", all([type => *, id => *, thread => *]),
            "finishing a thread's code sends a Thread Ended message";
        sleep 0.1;
        is-deeply $reactions.poll, Nil, "no more messages";
        is-deeply $outputs.poll, Nil, "no more outputs";

        await $proc.print("J0");
        is-deeply $outputs.receive, "OK J0", "joined thread 0";

        await $proc.print("Q9");
    });

