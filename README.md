[![Actions Status](https://github.com/raku-community-modules/MoarVM-Remote/actions/workflows/test.yml/badge.svg)](https://github.com/raku-community-modules/MoarVM-Remote/actions)

NAME
====

MoarVM::Remote - A library for working with the MoarVM remote debugging API

SYNOPSIS
========

```raku
# see examples in the test-suite for now
```

DESCRIPTION
===========

A Raku library to interface with MoarVM's remote debugger protocol.

It's mostly a thin layer above the wire format, [documented in the MoarVM repository](https://github.com/MoarVM/MoarVM/blob/master/docs/debug-server-protocol.md)

It exposes commands as methods, responses as Promises, and events/event streams as Supplies.

You can use the debug protocol with the Raku module/program [App::MoarVM::Debug](https://raku.land/github:edumentab/App::MoarVM::Debug). Another application that supports the debug protocol is [Comma](commaide.com).

MoarVM Remote Debug Protocol Design
===================================

The MoarVM Remote Debug Protocol is used to control a MoarVM instance over a socket, for the purposes of debugging. The VM must have been started in debug mode for this capability to be available (with the `--debug-port=12345` parameter).

The wire format
---------------

Rather than invent Yet Another Custom Binary Protocol, the MoarVM remote debug protocol uses [`MessagePack`](https://msgpack.org/) (through the [`Data::MessagePack`](https://raku.land/zef:raku-community-modules/Data::MessagePack) module). This has the advantage of easy future extensibility and existing support from other languages.

The only thing that is not MessagePack is the initial handshake, leaving the freedom to move away from MessagePack in a future version, should there ever be cause to do so.

Since MessagePack is largely just a more compact way to specify JSON, which is essentially a Raku data structure consisting of a hash with keys and values. Therefore all of the messages are show in Raku syntax. This is just for ease of reading: the Raku data structure will be automatically converted to/from MessagePack data on the wire.

### Initial Handshake

Upon receving a connection, MoarVM will immediately send the following **24** bytes if it is willing and able to accept the connection:

  * The string "MOARVM-REMOTE-DEBUG\0" encoded in ASCII

  * A big endian, unsigned, 16-bit major protocol version number - =item big endian, unsigned, 16-bit minor protocol version number

Otherwise, it will send the following response, explaining why it cannot, and then close the connection:

  * The string "MOARVM-REMOTE-DEBUG!" encoded in ASCII

  * A big endian, unsigned, 16-bit length for an error string explaining the rejection (length in bytes)

  * The error string, encoded in UTF-8

A client that receives anything other than a response of this form must close the connection and report an error. A client that receives an error response must report the error.

Otherwise, the client should check if it is able to support the version of the protocol that the server speaks. The onus is on clients to support multiple versions of the protocol should the need arise. See versioning below for more. If the client does not wish to proceed, it should simply close the connection.

If the client is statisfied with the version, it should send:

  * The string "MOARVM-REMOTE-CLIENT-OK\0" encoded in ASCII

For the versions of the protocol defined in this document, all further communication will be in terms of MessagePack messages.

MessagePack envelope
--------------------

Every exchange using MessagePack must be an object at the top level. The object must always have the following keys:

  * `type` which must have an integer value. This specifies the type of the message. Failing to include this field or failing to have its value be an integer is a protocol error, and any side receiving such a message should terminate the connection.

  * `id` which must have an integer value. This is used to associate a response with a request, where required. Any interaction initiated by the client should have an odd `id`, starting from 1. Any interaction initiated by the server should have an even `id`, starting from 2.

The object may contain further keys, which will be determined by message type.

Versioning
----------

Backwards-incompatible changes, if needed, will be made by incrementing the major version number. A client seeing a major version number it does not recognize or support must close the connection and not attempt any further interaction, and report an error.

The minor version number is incremented for backwards-compatible changes. A client may proceed safely with a higher minor version number of the protocol than it knows about. However, it should be prepared to accept and disregard message types that it does not recognize, as well as any keys in an object (encoded using MessagePack) that it does not recognize.

The client can use the minor version number to understand what features are supported by the remote MoarVM instance.

The MoarVM instance must disregard keys in a MessagePack object that it does not understand. For message types that it does not recognize, it must send a message of type "Message Type Not Understood" (format defined below); the connection should be left intact by MoarVM, and the client can decide how to proceed.

Security considerations
-----------------------

Any client connected to the debug protocol will be able to perform remote code execution using the running MoarVM instance. Therefore, MoarVM must only bind to `localhost` by default. It may expose an option to bind to further interfaces, but should display a warning about the dangers of this option.

Remote debugging should be performed by establishing a secure tunnel from the client to the server, for example using SSH port forwarding. This provides both authentication and protection against tampering with messages.

Message types
-------------

All messages defined here, unless stated otherwise, are supported in major version 1, minor version 0, of the protocol (also known as `1.0`).

All message types (basically a numeric ID, also exported as the `MessageType` enum) are described from the viewpoint of the client. Messages sent to the debug server are documented as "request", and messages coming back from the debug server are documented as "response".

When the term "user threads" is used, it means all threads apart from the spesh worker thread and the debug server thread itself.

### Message Type Not Understood (0)

Response indicating that a request was **not** understood, with the ID of the request that was not understood.

```raku
{
  type => 0,            # MT_MessageTypeNotUnderstood
  id   => $given-request-id
}
```

### Error Processing Message (1)

Response indicating that a problem occurred with the processing of a request, with the ID of the request that was not understood. The `reason` key should be a string explaining why.

```raku
{
  type   => 1,          # MT_ErrorProcessingMessage
  id     => $given-request-id,
  reason => $reason     # e.g. "Program already terminated"
}
```

### Operation Successful (2)

Response to acknowledge that a request was successfully performed (with ID of the request) when there is no further information to be given.

```raku
{
  type => 2,            # MT_OperationSuccessful
  id   => $given-request-id
}
```

### Is Execution Suspended Request (3)

Request to check whether execution of all user threads are currently suspended.

```raku
{
  type => 3,            # MT_IsExecutionSuspendedRequest
  id   => $new-request-id
}
```

### Is Execution Suspended Response (4)

Response indicating whether all user threads have been suspended, as observed by the `suspended` key being set to either `True` or `False`.

```raku
{
  type      => 4,       # MT_IsExecutionSuspendedResponse
  id        => $given-request-id,
  suspended => $suspended
}
```

### Suspend All (5)

Request to indicate that all user threads should be suspended. Response will always be "Operation Successful" regardless of whether the user threads had been suspended already or not.

```raku
{
  type => 5,            # MT_SuspendAll
  id   => $new-request-id
}
```

### Resume All (6)

Request to indicate that execution of all suspended threads should be resumed. Response will always be "Operation Successful" message regardless of whether the execution of user threads had been resumed already or not.

```raku
{
  type => 6,            # MT_ResumeAll
  id   => $new-request-id
}
```

### Suspend One (7)

Request to indicate that execution of a specific thread should be suspended, with the thread ID specified by the `thread` key.

Response will always be "Operation Successful" regardless of whether the execution of the indicated thread had been suspended already or not. If the thread ID was not recognized, then the response will be "Error Processing Message".

```raku
{
  type   => 7,          # MT_SuspendOne
  id     => $new-request-id,
  thread => $thread-id
}
```

### Resume One (8)

Request to indicate that execution of a specific thread should be resumed, with the thread ID specified by the `thread` key.

Response will always be "Operation Successful" regardless of whether the execution of the indicated thread had been resumed already or not. If the thread ID was not recognized, then the response will be "Error Processing Message".

```raku
{
  type   => 8,          # MT_ResumeOne
  id     => $new-request-id,
  thread => $thread-id
}
```

### Thread Started (9)

Unsolicited response whenever a new thread is started. The client can simply disregard it if it has no interest in this information.

The `thread` key contains the numeric thread ID that can be used in requests.

The `native_id` key contains the numeric thread ID that the OS has assigned to the thread.

The `app_lifetime` key contains `True` or `False`. `False` means that the process will only terminate when the thread has finished while `True` means that the thread will be killed when the main thread of the process terminates.

```raku
{
  type         => 9,    # MT_ThreadStarted
  id           => $an-even-id,
  thread       => $thread-id,
  native_id    => $OS_thread_id,
  app_lifetime => $app_lifetime
}
```

### Thread Ended (10)

Unsolicited response whenever a thread terminates. The client can simply disregard it if it has no interest in this information.

```raku
{
  type   => 10,         # MT_ThreadEnded
  id     => $an-even-id,
  thread => $thread-id
}
```

### Thread List Request (11)

Request a list of all threads, with some information about each one. This request may be sent at any time, whether or not the threads are suspended.

```raku
{
  type => 11,           # MT_ThreadListRequest
  id   => $new-request-id
}
```

### Thread List Response (12)

Response to a "Thread List Request". It contains an array of hashes, with one hash per running thread, providing information about that thread. It also contains an indication of whether the thread was suspended, and the number of locks it is currently holding.

The "name" key was added in version 1.2

```raku
{
  type => 12,           # MT_ThreadListResponse
  id   => $given-request-id,
  threads => [
    {
      thread       => $thread-id      # e.g. 1
      native_id    => $OS_thread_id,  # e.g. 1010
      app_lifetime => $app_lifetime,  # e.g. True
      suspended    => $suspended      # e.g. True
      num_locks    => $num_locks,     # e.g. 1
      name         => $name           # e.g. "AffinityWorker"
    },
    {
      thread       => $thread-id      # e.g. 3
      native_id    => $OS_thread_id,  # e.g. 1020
      app_lifetime => $app_lifetime,  # e.g. True
      suspended    => $suspended      # e.g. False
      num_locks    => $num_locks,     # e.g. 0
      name         => $name           # e.g. "Supervisor"
    }
  ]
}
```

```raku
=head3 Thread Stack Trace Request (13)

Request the stack trace of a thread.  This is only allowed if that
thread is suspended; an "Error Processing Message" response will be
returned otherwise.

=begin code :lang<raku>

{
  type   => 13,         # MT_ThreadStackTraceRequest
  id     => $new-request-id,
  thread => $thread_id  # e.g. 3
}
```

### Thread Stack Trace Response (14)

Response to a "Thread Stack Trace Request". It contains an array of hashes, each representing a stack frame (topmost first) that are currently on the call stack of that thread.

The `bytecode_file` key will be either a string or `nil` if the bytecode only exists "in memory" (for example, due to an `EVAL`).

The `name` key will be an empty string in the case that the code for that frame has no name.

The `type` key is the debug name of the type of the code object, or `Nil` if there is none.

```raku
{
  type   => 14,           # MT_ThreadStackTraceResponse
  id     => $given-request-id,
  frames => [
    {
      file          => $file,          # e.g. "path/to/source/file"
      line          => $line,          # e.g. 22
      bytecode_file => $bytecode_file, # e.g. "path/to/bytecode/file"
      name          => $name,          # e.g. "some-method"
      type          => $type           # e.g. "Method"
    },
    {
      file          => $file,          # e.g. "path/to/source/file"
      line          => $line,          # e.g. 12
      bytecode_file => $bytecode_file, # e.g. "path/to/bytecode/file"
      name          => $name,          # e.g. "",
      type          => $type           # e.g. "Block"
    },
    {
      file          => $file,          # e.g. "path/to/another/source/file"
      line          => $line,          # e.g. 123
      bytecode_file => $bytecode_file, # e.g. "path/to/another/bytecode/file"
      name          => $name,          # e.g. "foo"
      type          => $type           # e.g. Nil
    }
  ]
}
```

```raku
=head3 Set Breakpoint Request (15)

Request to set a breakpoint at the specified location, or the closest
possible location to it.

The C<file> key refers to the source file.

If the C<suspend> key is set to C<True> then execution of all threads
will be suspended when the breakpoint is hit. In either case, the client
will be notified.  The use of non-suspend breakpoints is for counting
the number of times a certain point is reached.

If the C<stacktrace> key is set to C<true> then a stack trace of the
location where the breakpoint was hit will be included.  This can be
used both with and without `suspend`; with the C<suspend> key set to
C<True> it can save an extra round-trip to request the stack location,
while with C<suspend> key set to C<False> it can be useful for features
like "capture a stack trace every time foo is called".

{
  type       => 15,     # MT_SetBreakpointRequest
  id         => $new-request-id,
  file       => $file,       # e.g. "path/to/source/file"
  line       => $line,       # e.g. 123
  suspend    => $suspend,    # e.g. True
  stacktrace => $stacktrace  # e.g. False
}
```

### Set Breakpoint Confirmation (16)

Response to confirm that a breakpoint has been set.

The `line` key indicates the actual line that the breakpoint was placed on, if there was no exactly annotation match. This message will be sent before any breakpoint notifications; the ID will match the ID specified in the breakpoint request.

```raku
{
  type => 16,           # MT_SetBreakpointConfirmation
  id   => $given-request-id,
  line => $line  # e.g. 16
}
```

### Breakpoint Notification (17)

Unsolicited response whenever a breakpoint is reached. The ID will match that of the breakpoint request.

The `frames` key will be `Nil` if the `stacktrace` key of the breakpoint request was `False`. Otherwise, it will contain an array of hashesh describing the stack frames, formatted as in the "Thread Stack Trace Response" message type.

```raku
{
  type   => 17,         # MT_BreakpointNotification
  id     => $given-request-id,
  thread => $thread-id, # e.g. 1
  frames => $frames     # Nil or [ ... ]
}
```

### Clear Breakpoint (18)

Request to clear a breakpoint. The line number must be the one the breakpoint was really set on (indicated in the "Set Breakpoint Confirmation" message). This will be followed by an "Operation Successful" response after clearing the breakpoint.

```raku
{
  type => 18,           # MT_ClearBreakpoint
  id   => $new-request-id,
  file => $file,  # e.g. "path/to/source/file",
  line => $line   # e.g. 123
}
```

### Clear All Breakpoints (19)

Request to clear all breakpoints that have been set. This will be followed by an "Operation Successful" response after clearing all breakpoints.

```raku
{
  type => 19,           # MT_ClearAllBreakpoints
  id   => $new-request-id
}
```

### Single Step (aka. Step Into) (20)

Request to run a suspended thread until the next program point, where program points are determined by either a change of frame or a change of line number in the bytecode annotation table.

The thread this is invoked on must be suspended, and will be returned to suspended state after the step has taken place, followed by a "Step Completed" response.

```raku
{
  type   => 20,         # MT_StepInto
  id     => $new-request-id,
  thread => $thread-id  # e.g. 1
}
```

### Step Over (21)

Request to run a suspended thread until the next program point either in the same frame or in a calling frame (but not in any called frames below this point), to return to suspended state after the steps have taken place, followed by a "Step Completed" response.

```raku
{
  type   => 21,         # MT_StepOver
  id     => $new-request-id,
  thread => $thread-id  # e.g. 1
}
```

### Step Out (22)

Request to run a suspended thread until the program returns into the specified frame. After which the thread will be returned to suspended state, followed by a "Step Completed" response.

```raku
{
  type   => 22,         # MT_StepOut
  id     => $new-request-id,
  thread => $thread-id  # e.g. 1
}
```

### Step Completed (23)

Response to acknowledge that a stepping operation was completed.

The `id` key matches the ID that of the step request.

The `frames` key contains an array of hashes that contains the stacktrace after stepping; the `file` and `line` keys will be of the current location in the topmost frame.

```raku
{
  type   => 23,         # MT_StepCompleted
  id     => $given-request-id,
  thread => $thread-id, # e.g. 1
  frames => [
    ...
  ]
}
```

### Release Handles (24)

Handles are integers that are mapped to an object living inside of the VM. For so long as the handle is alive, the object will be kept alive by being in the handles mapping table. Therefore, it is important that, when using any instructions that involve handles, they are released afterwards. Otherwise, the debug client can induce a managed memory leak. This command is confirmed with an Operation Successful message.

```raku
{
  type => 24,
  id => $id,
  handles => [42, 100]
}
```

### Handle Result (25)

This is a common response message send by MoarVM for requests that ask for an object handle. The ID will match that of the request. Remember to release handles when the debug client no longer needs them by sending a Release Handles message. The `0` handle represents the VM Null value.

```raku
{
  type => 25,
  id => $id,
  handle => 42
}
```

### Context Handle (26)

Sent by the client to allocate a context object handle for the specified frame (indicated by the depth relative to the topmost frame on the callstack, which is frame 0) and thread. This can only be used on a thread that is suspended. A context handle is just an object handle, where the object happens to have the MVMContext REPR, and the result is delivered as a Handle Result message.

```raku
{
  type => 26,
  id => $id,
  thread => 1,
  frame => 0
}
```

### Context Lexicals Request (27)

Sent by the client to request the values of lexicals in a given context. The `handle` key must be a context handle. The response comes as a Context Lexicals Response message.

```raku
{
  type => 27,
  id => $id,
  handle => 1234
}
```

### Context Lexicals Response (28)

Contains the results of introspecting a context. For natively typed values, the value is included directly in the response. For object lexicals, an object handle will be allocated for each one. This will allow for further introspection of the object; take care to release it. The debug name of the type is directly included, along with whether it's concrete (as opposed to a type object) and a container type that could be decontainerized. The `kind` key may be one of `obj`, `int`, `num`, or `str`.

```raku
{
  type => 28,
  id => $id,
  lexicals => {
            "$x => {
                "kind => "obj",
                "handle => 1234,
                "type => "Scalar",
                "concrete => true,
                "container => true
            },
            "$i => {
                "kind => "int",
                "value => 42
            },
            "$s => {
                "kind => "str",
                "value => "Bibimbap"
            }
        }
}
```

### Outer Context Request (29)

Used by the client to gets a handle to the outer context of the one passed. A Handle Result message will be sent in response. The null handle (0) will be sent if there is no outer.

```raku
{
  type => 29,
  id => $id,
  handle => 1234
}
```

### Caller Context Request (30)

Used by the client to gets a handle to the caller context of the one passed. A Handle Result message will be sent in response. The null handle (0) will be returned if there is no caller.

```raku
{
  type => 30,
  id => $id,
  handle => 1234
}
```

### Code Object Handle (31)

Sent by the client to allocate a handle for the code object of the specified frame (indicated by the depth relative to the topmost frame on the callstack, which is frame 0) and thread. This can only be used on a thread that is suspended. If there is no high-level code object associated with the frame, then the null handle (0) will be returned. The response is delivered as a Handle Result message.

```raku
{
  type => 31,
  id => $id,
  thread => 1,
  frame => 0
}
```

### Object Attributes Request (32)

Used by the client to introspect the attributes of an object. The response comes as an Object Attributes Response message.

```raku
{
  type => 32,
  id => $id,
  handle => 1234
}
```

### Object Attributes Response (33)

Contains the results of introspecting the attributes of an object. If the object cannot have any attributes, the `attributes` key will be an empty array. For natively typed attributes, the value is included directly in the response. For object attributes, an object handle will be allocated for each one. This will allow for further introspection of the object; take care to release it. The debug name of the type is directly included, along with whether it's concrete (as opposed to a type object) and a container type that could be decontainerized. The `kind` key may be one of `obj`, `int`, `num`, or `str`. Since attributes with the same name may exist at multiple inheritance levels, an array is returned with the debug name of the type at that level under the `class` key.

```raku
{
  type => 33,
  id => $id,
  attributes => [
            {
                "name => "$!x",
                "class => "FooBase"
                "kind => "obj",
                "handle => 1234,
                "type => "Scalar",
                "concrete => true,
                "container => true
            },
            {
                "name => "$!i",
                "class => "Foo",
                "kind => "int",
                "value => 42
            }
        ]
}
```

### Decontainerize Handle (34)

Used to decontainerize a value in a container (such as a Raku `Scalar`). The handle to the object that results is returned in a Handle Result message. If this is not a container type, or if an exception occurs when trying to do the decontainerization, an Error Processing Message response will be sent by MoarVM instead. A target thread to perform this operation on is required, since it may be required to run code (such as a `Proxy`); the thread must be suspended at the point this request is issued, and will be returned to suspended state again after the decontainerization has taken place. Note that breakpoints may be hit and will be fired during this operation.

```raku
{
  type => 34,
  id => $id,
  thread => 1,
  handle => 1234
}
```

### Find Method (35)

**NOTE**: This request is no longer supported by newer MoarVM releases since the conversion to the new dispatch system (`new-disp`); current releases will send Error Processing Message instead of the following behavior.

Used by the client to find a method on an object that it has a handle to. The handle to the method that results is returned in a Handle Result message, with the null object handle (0) indicating no method found. If an exception occurs when trying to do the method resolution, an Error Processing Message response will be sent by MoarVM instead. A target thread to perform this operation on is required, since it may be required to run code (such as `find_method`) in a custom meta-object); the thread must be suspended at the point this request is issued, and will be returned to suspended state again after the lookup has taken place. Note that breakpoints may be hit and will be fired during this operation.

```raku
{
  type => 35,
  id => $id,
  thread => 1,
  handle => 1234,
  name => "frobify",
}
```

### Invoke (36)

Used by the client to invoke an object that it has a handle to, which should be some kind of code object. The arguments may be natives or other objects that the client has a handle for. The results will be returned in an Invoke Result message. A target thread to perform this operation on is required. The thread must be suspended at the point this request is issued, and will be returned to suspended state again after the lookup has taken place. Note that breakpoints may be hit and will be fired during this operation.

Named arguments require a "name" entry in the argument's map that gives a string.

```raku
{
  type => 36,
  id => $id,
  thread => 1,
  handle => 1235,
  arguments => [
            {
                "kind => "obj",
                "handle => 1234
            },
            {
                "kind => "str",
                "value => "Bulgogi"
            }
        ]
}
```

### Invoke Result (37)

Contains the result of an Invoke message. If the result was of an object type then a handle to it will be returned. If the invoke resulted in an exception, then the `crashed` key will be set to a true value, and the `result` handle will point to the exception object instead. Object result example:

```raku
{
  type => 37,
  id => $id,
  crashed => false,
  kind => "obj",
  handle => 1234,
  obj_type => "Int",
  concrete => true,
  container => false
}
```

Native int result example:

```raku
{
  type => 37,
  id => $id,
  crashed => false,
  kind => "int",
  value => 42
}
```

Exception result:

```raku
{
  type => 37,
  id => $id,
  crashed => true,
  kind => "obj",
  handle => 1234,
  obj_type => "X::AdHoc",
  concrete => true,
  container => false
}
```

### Unhandled Exception (38)

This message is sent by MoarVM when an unhandled exception occurs. All threads will be suspended. A handle to the exception object is included, together with the thread it occurred on and the stack trace of that thread. So far as it is able to do so, MoarVM will allow operations such as introspecting the context, resolving methods, decontainerizing values, and invoking code.

```raku
{
  type => 38,
  id => $id,
  thread => 1,
  handle => 1234,
  frames => [
            {
                "file => "path/to/source/file",
                "line => 22,
                "bytecode_file => "path/to/bytecode/file",
                "name => "some-method",
                "type => "Method"
            },
            {
                "file => "path/to/source/file",
                "line => 12,
                "bytecode_file => "path/to/bytecode/file",
                "name => "",
                "type => "Block"
            }
        ]
}
```

### Operation Unsuccessful (39)

A generic message sent by MoarVM if something went wrong while handling a request. This message is not in current use; Error Processing Message (1) will be sent instead (as that includes a reason message).

```raku
{
  type => 39,
  id => $id
}
```

### Object Metadata Request (40)

Used by the client to get additional information about an object that goes beyond its actual attributes. Can include miscellaneous details from the REPRData and the object's internal state if it's concrete.

Additionally, all objects that have positional, associative, or attribute features will point that out in their response.

```raku
{
  type => 40,
  id => $id,
  handle => 1234
}
```

### Object Metadata Response (41)

Contains the results of introspecting the metadata of an object.

Every object has `reprname`. All concrete objects have `size` and `unmanaged_size` fields.

Objects also include `positional_elems` and `associative_elems` for objects that have positional and/or associative features.

`pos_features`, `ass_features`, and `attr_features` inform the client which of the requests 42 ("Object Positionals Request"), 44 ("Object Associatives Request"), or 32 ("Object Attributes Request") will give useful results.

```raku
{
  type => 41,
  id => $id,
  metadata => {
            "reprname => "VMArray",
            "size => 128,
            "unmanaged_size => 1024,

            "vmarray_slot_type => "num32",
            "vmarray_elem_size => 4,
            "vmarray_allocated => 128,
            "vmarray_offset => 40,

            "positional_elems => 12,

            "pos_features => true,
            "ass_features => false,
            "attr_features => false,
        },
}
```

### Object Positionals Request (42)

Used by the client to get the contents of an object that has positional features, like an array.

```raku
{
  type => 42,
  id => $id,
  handle => 12345
}
```

### Object Positionals Response (43)

The `kind` field can be "int", "num", "str" for native arrays, or "obj" for object arrays.

In the case of an object array, every entry in the `contents` field will be a map with keys `type`, `handle`, `concrete`, and `container`.

For native arrays, the array contents are sent as their corresponding messagepack types.

Native contents:

```raku
{
  type => 43,
  id => $id,
  kind => "int",
  start => 0,
  contents => [
            1, 2, 3, 4, 5, 6
        ]
}
```

Object contents:

```raku
{
  type => 43,
  id => $id,
  kind => "obj",
  start => 0,
  contents => [
            {
                "type => "Potato",
                "handle => 9999,
                "concrete => true,
                "container => false
            },
            {
                "type => "Noodles",
                "handle => 10000,
                "concrete => false,
                "container => false
             }
         ]
     }
```

### Object Associatives Request (44)

Used by the client to get the contents of an object that has associative features, like a hash.

```raku
{
  type => 44,
  id => $id,
  handle => 12345
}
```

### Object Associatives Response (45)

All associative `contents` are of `kind` "obj", and are sent as an outer map with string keys. Each outer value is an inner map with `type`, `handle`, `concrete`, and `container` keys, similar to Object Positionals Response (43).

```raku
{
  type => 45,
  id => $id,
  kind => "obj"
  contents => {
            "Hello => {
                "type => "Poodle",
                "handle => 4242,
                "concrete => true,
                "container => false
            },
            "Goodbye => {
                "type => "Poodle",
                "handle => 4242,
                "concrete => true,
                "container => false
            }
        }
}
```

### Handle Equivalence Request (46)

Ask the debugserver to check if handles refer to the same object.

```raku
{
  type => 46,
  id => $id,
  handles => [
            1, 2, 3, 4, 5, 6, 7
        ]
}
```

### Handle Equivalence Response (47)

For any object that is referred to by multiple handles from the request, return a list of all the handles that belong to the given object.

```raku
{
  type => 47,
  id => $id,
  classes => [
            [1, 3],
            [2, 5, 7]
        ]
}
```

### HLL Symbol Request (48)

MoarVM features a mechanism for objects and types to be registered with an HLL, for example "nqp" or "perl6" or "raku". This request allows you to find the available HLLs, a given HLL's keys, and the value for a given key.

The first two variants will result in an HLL Symbol Response, while the third one will result in a Handle Result message.

Get all HLL names:

```raku
{
  type => 48,
  id => $id,
}
```

Get an HLL's symbol names:

```raku
{
  type => 48,
  id => $id,
  HLL => "nqp"
}
```

Get the value for a symbol:

```raku
{
  type => 48,
  id => $id,
  HLL => "nqp",
  name => "
}
```

### HLL Symbol Response (49)

For cases where the HLL Symbol Request results in a list of strings, i.e. when all HLL names or an HLL's symbols are requested, the HLL Symbol Response will be emitted.

```raku
{
  type => 49,
  id => $id,
  keys => [
            "one",
            "two",
        ]
}
```

AUTHOR
======

- Timo Paulssen - Raku Community

COPYRIGHT AND LICENSE
=====================

Copyright 2011 - 2020 Timo Paulssen

Copyright 2021 - 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

