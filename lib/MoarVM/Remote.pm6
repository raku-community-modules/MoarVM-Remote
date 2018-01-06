use Data::MessagePack;
use Data::MessagePack::StreamingUnpacker;

our enum MessageType is export <
    MT_MessageTypeNotUnderstood
    MT_ErrorProcessingMessage
    MT_OperationSuccessful
    MT_IsExecutionSuspendedRequest
    MT_IsExecutionSuspendedResponse
    MT_SuspendAll
    MT_ResumeAll
    MT_SuspendOne
    MT_ResumeOne
    MT_ThreadStarted
    MT_ThreadEnded
    MT_ThreadListRequest
    MT_ThreadListResponse
    MT_ThreadStackTraceRequest
    MT_ThreadStackTraceResponse
    MT_SetBreakpointRequest
    MT_SetBreakpointConfirmation
    MT_BreakpointNotification
    MT_ClearBreakpoint
    MT_ClearAllBreakpoints
    MT_StepInto
    MT_StepOver
    MT_StepOut
    MT_StepCompleted
    MT_ReleaseHandles
    MT_HandleResult
    MT_ContextHandle
    MT_ContextLexicalsRequest
    MT_ContextLexicalsResponse
    MT_OuterContextRequest
    MT_CallerContextRequest
    MT_CodeObjectHandle
    MT_ObjectAttributesRequest
    MT_ObjectAttributesResponse
    MT_DecontainerizeHandle
    MT_FindMethod
    MT_Invoke
    MT_InvokeResult
    MT_UnhandledException
>;

class X::MoarVM::Remote::ProtocolError is Exception {
    has $.attempted;

    method message {
        "Something went wrong in communicating with the server while trying to $.attempted"
    }
}

class X::MoarVM::Remote::MessageType is Exception {
    has $.type;

    method message {
        "Message type $.type not understood by remote."
    }
}

class X::MoarVM::Remote::MessageProcessing is Exception {
    has $.reason;

    method message {
        "Remote encountered an error processing message: $.reason"
    }
}

class X::MoarVM::Remote::Version is Exception {
    has @.versions;

    method message {
        "Incompatible remote version: @.versions[]"
    }
}

sub recv32be($inbuf) {
    my $buf = $inbuf.splice(0, 4);
    return [+] $buf.list >>+<>> (24, 16, 8, 0);
}
sub recv16be($inbuf) {
    my $buf = $inbuf.splice(0, 2);
    return [+] $buf.list >>+<>> (8, 0);
}
sub send32be($sock, $num) {
    my $buf = Buf[uint8].new($num.polymod(255, 255, 255, 255)[^4].reverse);
    $sock.write($buf);
}

class MoarVM::Remote {
    has $!sock;
    has $!worker;

    has Lock $!queue-lock .= new;
    has @!request-promises;

    has Lock $!id-lock .= new;
    has int32 $!req_id = 1;

    has Supply $!worker-events;

    has Version $.remote-version;

    has Supplier $!events-supplier = Supplier::Preserving.new;

    has Supply $.events = $!events-supplier.Supply;

    submethod TWEAK(:$!sock, :$!worker-events) {
        self!start-worker;
    }

    sub take-greeting(buf8 $buffer) {
        if $buffer.elems >= "MOARVM-REMOTE-DEBUG\0".chars + 4 {
            if $buffer.subbuf(0, "MOARVM-REMOTE-DEBUG\0".chars).list eqv  "MOARVM-REMOTE-DEBUG\0".encode("ascii").list {
                $buffer.splice(0, "MOARVM-REMOTE-DEBUG\0".chars);
                if (my $major = recv16be($buffer)) != 1 || (my $minor = recv16be($buffer)) != 0 {
                    die X::MoarVM::Remote::Version.new(:versions($major, $minor));
                }
                return Version.new("$major.$minor");
            }
        }
        False
    }

    method connect(MoarVM::Remote:U: Int $port) {
        start {
            my @sleep-intervals = 0.5, 1, 1, 2, 4, Failure.new("connection retries exhausted");
            my $result;
            loop {
                my $sockprom = Promise.new;
                my $handshakeprom = Promise.new;
                my $remote-version = Promise.new;

                my $without-handshake = supply {
                    whenever IO::Socket::Async.connect("localhost", $port) -> $sock {
                        $sockprom.keep($sock);

                        my $handshake-state = 0;
                        my $buffer = buf8.new;

                        whenever $sock.Supply(:bin) {
                            if $handshake-state == 0 {
                                $buffer.append($_);
                                if take-greeting($buffer) -> $version {
                                    await $sock.write("MOARVM-REMOTE-CLIENT-OK\0".encode("ascii"));
                                    $remote-version.keep($version);
                                    $handshake-state = 1;
                                    $handshakeprom.keep();
                                    if $buffer {
                                        die X::MoarVM::Remote::ProtocolError.new(attempted => "receiving the greeting - and only the greeting");
                                    }
                                }
                            } else {
                                emit $_;
                            }
                        }
                    }
                }

                my $without-handshake-shared = $without-handshake.share;

                $without-handshake-shared.tap({;}, quit => { $sockprom.break($_) });

                my $worker-events = Data::MessagePack::StreamingUnpacker.new(source => $without-handshake-shared).Supply;

                my $res = self.bless(sock => (await $sockprom), :$worker-events, remote-version => await $remote-version);
                await $handshakeprom;
                $result = $res;
                last;
                CATCH {
                    when .message.contains("connection refused") {
                        sleep @sleep-intervals.shift;
                    }
                }
            }
            $result;
        }
    }

    method !start-worker {
        $!worker //= start react {
            whenever $!worker-events -> $message {
                my $task;
                $!queue-lock.protect: {
                    $task = @!request-promises.grep(*.key == $message<id>).head.value;
                    @!request-promises .= grep(*.key != $message<id>) with $task;
                }
                without $task {
                    note "Got notification from moarvm: $message.perl()";
                    $!events-supplier.emit($message);
                    next;
                }
                note "got reply from moarvm: $message.perl()";
                if $message<type> == 0 {
                    $task.break(X::MoarVM::Remote::MessageType.new(type => $message<type>));
                } elsif $message<type> == 1 {
                    $task.break(X::MoarVM::Remote::MessageProcessing.new(reason => $message<reason>));
                } else {
                    $task.keep($message)
                }
                LAST $!events-supplier.done();
            }
            QUIT {
                $!events-supplier.quit($_);
            }
        }
    }

    method !get-request-id {
        $!id-lock.protect: {
            my $res = $!req_id;
            $!req_id += 2;
            $res
        }
    }

    method !send-request($type, *%data) {
        die "Cannot send request; Worker has finished running." if $!worker.status === PromiseStatus::Kept;

        if $!worker.status === PromiseStatus::Broken {
            note "Cannot send request; Worker has crashed!";
            $!worker.result.self;
        }

        my $id = self!get-request-id;

        my %data-to-send = %data, :$id, :$type;

        my $packed = Data::MessagePack::pack(%data-to-send);

        note $packed;

        start {
            my $prom = Promise.new;
            $!queue-lock.protect: {
                @!request-promises.push($id => $prom.vow);
            }

            await $!sock.write($packed);
            await $prom;
        }
    }

    multi method is-execution-suspended() {
        self!send-request(MT_IsExecutionSuspendedRequest).then({
            say .result.perl;
            .result<suspended>
        })
    }

    method threads-list {
        self!send-request(MT_ThreadListRequest).then({
            .result<threads>;
        })
    }

    multi method suspend(Int $thread) {
        self!send-request(MT_SuspendOne, :$thread).then({
            .result<type> == 3
        })
    }
    multi method resume(Int $thread) {
        self!send-request(MT_ResumeOne, :$thread).then({
            .result<type> == 3
        })
    }

    multi method suspend(Whatever) {
        self!send-request(MT_SuspendAll).then({
            .result<type> == 3
        })
    }
    multi method resume(Whatever) {
        self!send-request(MT_ResumeAll).then({
            .result<type> == 3
        })
    }

    method context-handle(Int $thread, Int $frame) {
        self!send-request(MT_ContextHandle, :$thread, :$frame).then({
            .result<handle>;
        })
    }
    method caller-context-handle(Int $handle) {
        self!send-request(MT_CallerContextRequest, :$handle).then({
            .result<handle>;
        })
    }
    method outer-context-handle(Int $handle) {
        self!send-request(MT_OuterContextRequest, :$handle).then({
            .result<handle>;
        })
    }
    method coderef-handle(Int $thread, Int $frame) {
        self!send-request(MT_CodeObjectHandle, :$thread, :$frame).then({
            .result<handle>;
        })
    }

    method lexicals(Int $handle) {
        self!send-request(MT_ContextLexicalsRequest, :$handle).then({
            .result<lexicals>;
        })
    }

    method attributes(Int $handle) {
        self!send-request(MT_ObjectAttributesRequest, :$handle).then({
            .result<attributes>;
        })
    }

    method dump(Int $thread) {
        self!send-request(MT_ThreadStackTraceRequest, :$thread).then({
            .result<frames>;
        })
    }
}
