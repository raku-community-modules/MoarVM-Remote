use v6.d.PREVIEW;

use lib $?FILE.IO.sibling("lib");

use Test;

use MoarVM::Remote;
use MoarRemoteTest;

plan 1;


Promise.in(10).then: { note "Did not finish test in 10 seconds. Considering this a failure."; exit 1 }

{
my $T0-id;
run_testplan [
    command => CreateLock => 0,
    command => CreateThread => 0,
    assert  => "NoEvent",
    command => RunThread => 0,
    receive =>
            [type => MT_ThreadStarted,
             thread => $T0-id,
             app_lifetime => 0],
    assert  => "NoEvent",
    assert  => "NoOutput",
    command => UnlockThread => 0,
    receive =>
            [type => MT_ThreadEnded,
             thread => $T0-id],
    assert  => "NoEvent",
    assert  => "NoOutput",
    command => JoinThread => 0,
    command => Quit => 0,
]
}
