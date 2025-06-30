[![Actions Status](https://github.com/raku-community-modules/MoarVM-Remote/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/MoarVM-Remote/actions) [![Actions Status](https://github.com/raku-community-modules/MoarVM-Remote/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/MoarVM-Remote/actions) [![Actions Status](https://github.com/raku-community-modules/MoarVM-Remote/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/MoarVM-Remote/actions)

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

MESSAGE TYPES
=============

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

The `name` key was added in version 1.2.

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

### Thread Stack Trace Request (13)

Request the stack trace of a thread. This is only allowed if that thread is suspended; an "Error Processing Message" response will be returned otherwise.

```raku
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

### Set Breakpoint Request (15)

Request to set a breakpoint at the specified location, or the closest possible location to it.

The `file` key refers to the source file.

If the `suspend` key is set to `True` then execution of all threads will be suspended when the breakpoint is hit. In either case, the client will be notified. The use of non-suspend breakpoints is for counting the number of times a certain point is reached.

If the `stacktrace` key is set to `true` then a stack trace of the location where the breakpoint was hit will be included. This can be used both with and without `suspend`; with the `suspend` key set to `True` it can save an extra round-trip to request the stack location, while with `suspend` key set to `False` it can be useful for features like "capture a stack trace every time foo is called".

```raku
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

Handles are integers that are mapped to an object living inside of the VM. For so long as the handle is alive, the object will be kept alive by being in the handles mapping table.

Therefore, it is important that, when using any instructions that involve handles, they are released afterwards when they are not needed anymore. Otherwise the client can induce a managed memory leak.

The `handles` key should be specified with an array of integers matching the handles to be released.

Responds with an "Operation Successful" message if all specified handles were successfully released.

```raku
{
  type    => 24,        # MT_ReleaseHandles
  id      => $id,
  handles => @array     #  e.g. [42, 100]
}
```

### Handle Result (25)

Response for requests that ask for an object handle. The ID will match that of the request. The value `0` represents the `VMNull` value.

```raku
{
  type   => 25,         # MT_HandleResult
  id     => $given-request-id,
  handle => $integer    # e.g. 42
}
```

### Context Handle (26)

Request to allocate a context object handle for the specified frame (indicated by the depth relative to the topmost frame on the callstack, which is frame 0) and thread.

This can only be used on a thread that is suspended. A context handle is just an object handle, where the object happens to have the `MVMContext` REPR.

Followed by a "Handle Result" response.

```raku
{
  type   => 26,         # MT_ContextHandle
  id     => $new-request-id,
  thread => $thread-id    # e.g. 1
  frame  => $frame-index  # e.g. 0
}
```

### Context Lexicals Request (27)

Request the values of lexicals in a given context, followed by a "Context Lexicals" response.

The `handle` key must be a context handle.

```raku
{
  type   => 27,         # MT_ContextLexicalsRequest
  id     => $new-request-id,
  handle => $handle-id  # e.g. 1234
}
```

### Context Lexicals Response (28)

Response containing the results of introspecting a context. The `lexicals` key contains a hash of hashes, in which the inner hash has information about the lexicals in that context, with the name of the lexical as the key.

For natively typed values, the value is included directly in the response.

For object lexicals, a new object handle will be allocated for each object encountered. This will allow for further introspection of the object (always make sure to release the associated handles if the object is no longer needed).

The debug name of the type is directly included in the `type` key, along with whether it's concrete (as opposed to a type object) and a container type that could be decontainerized.

The `kind` key may be one of "int", "num", or "str" (for native values) or "obj" for objects.

```raku
{
  type     => 28,       # MT_ContextLexicalsResponse
  id       => $given-request-id,
  lexicals => {
    '$x' => {
      kind      => "obj",
      handle    => $handle,    # e.g. 1234
      type      => $type,      # e.g. "Scalar"
      concrete  => $concrete,  # True or False
      container => $container  # True or False
    },
    '$i' => {
      kind  => "int",
      value => 42
    },
    '$s' => {
      kind  => "str",
      value => "Bibimbap"
    }
  }
}
```

### Outer Context Request (29)

Request a handle to the outer context of the context for which the handle is being passed, followed by a "Handle Result" response.

The null handle (`0`) will be given if there is no outer context.

```raku
{
  type   => 29,         # MT_OuterContextRequest
  id     => $new-request-id,
  handle => $handle     # e.g. 1234
}
```

### Caller Context Request (30)

Request to create a handle for the caller context of the context of which the handle is being passed, followed by a "Handle Result" response.

The null handle (`0`) will be given if there is no outer caller.

```raku
{
  type   => 30,         # MT_CallerContextRequest
  id     => $new-request-id,
  handle => $handle     # e.g. 1234
}
```

### Code Object Handle (31)

Request a handle for the code object of the specified frame (indicated by the depth relative to the topmost frame on the callstack, which is frame 0) and thread ID, followed by a "Handle Result" response.

This can only be used on a thread that is suspended.

If there is no high-level code object associated with the frame, then the null handle (`0`) will be given.

```raku
{
  type   => 31,         # MT_CodeObjectHandle
  id     => $new-request-id,
  thread => $thread-id,   # e.g. 1
  frame  => $frame-index  # e.g. 0
}
```

### Object Attributes Request (32)

Request information about the attributes of an object by its given handle, followed by an "Object Attributes" response.

```raku
{
  type   => 32,         # MT_ObjectAttributesRequest
  id     => $new-request-id,
  handle => $handle     # e.g. 1234
}
```

### Object Attributes Response (33)

Response containing the information about the attributes of an object (specified by its handle in a "Object Attributes" request).

The `attributes` key contains a list of hashes with the attribute information. If the object does not have any attributes, then the `attributes` key will be an empty array.

For natively typed attributes, the value is included directly in the response. For object attributes, an object handle will be allocated for each one. This will allow for further introspection of the object.

The debug name of the type is directly included, along with whether it's concrete (as opposed to a type object) and a container type that could be decontainerized.

The <kind> key may be one of "int", "num", or "str" for native values, or "obj" for objest. Since attributes with the same name may exist at multiple inheritance levels, an array is returned with the debug name of the class at that level with the `class` key.

```raku
{
  type       => 33,     # MT_ObjectAttributesResponse
  id         => $given-request-id,
  attributes => [
    {
      name      => '$!x',
      class     => $class,     # e.g. "FooBase"
      kind      => "obj",
      handle    => $handle,    # e.g. 1235
      type      => $type,      # e.g. "Scalar"
      concrete  => $concrete,  # True or False
      container => $container  # True or False
    },
    {
      name  => '$!i',
      class => $class,  # e.g. "Foo"
      kind  => "int",
      value => 42
    }
  ]
}
```

### Decontainerize Handle (34)

Request a handle for the decontainerized object indicated by its handle, followed by a "Handle Result" response.

Respond with an "Error Processing" response if the indicated object is not a container type, or if an exception occurred when trying to do the decontainerization.

A target thread to perform this operation on is required, since it may be required to run code (such as code inside a `Proxy` container). The thread must be suspended at the point the request made, and will be returned to suspended state again after the decontainerization has taken place and a new handle was created.

Note that breakpoints may be hit and will be fired during this operation.

```raku
{
  type   => 34,         # MT_DecontainerizeHandle
  id     => $new-request-id,
  thread => $thread-id, # e.g. 1
  handle => $handle     # e.g. 1234
}
```

### Invoke (36)

Request invocation of a code object (as indicated by its handle), followed by an "Invoke Result" response.

The `arguments` key should contain a (possibly empty) array of hashes, one for each argument.

Arguments may be native values or other objects specified by their `handle`. Named arguments require a `name` key with the name of the named argument.

A target thread to perform this operation on is required. The thread must be suspended at the point this request is made, and will be returned to suspended state again after the execution has taken place.

Note that breakpoints may be hit and will be fired during this operation.

```raku
{
  type      => 36,      # MT_Invoke
  id        => $new-request-id,
  thread    => $thread-id,   # e.g. 1
  handle    => $code-hande,  # e.g. 1235,
  arguments => [
    {
      kind   => "obj",
      handle => $handle  # e.g. 1234
    },
    {
      kind  => "str",
      name  => "frobnicate",
      value => "Bulgogi"
    }
  ]
}
```

### Invoke Result (37)

Response to an "Invoke" request with the result in the `result` key.

If the result was not a native value, then a handle to the object will be created and returned in the `handle` key.

If the invocation resulted in an exception, then the `crashed` key will be set to a true value: the `result` key will then be about the `Exception` object instead.

Object result example:

```raku
{
  type      => 37,      # MT_InvokeResult
  id        => $given-request-id,
  crashed   => False,
  kind      => "obj",
  handle    => $handle,    # e.g. 1256
  obj_type  => $obj_type,  # e.g. "Int",
  concrete  => $concrete,  # True or False
  container => $container  # True or False
}
```

Native int result example:

```raku
{
  type    => 37,        # MT_InvokeResult
  id      => $given-request-id,
  crashed => False,
  kind    => "int",
  value   => 42
}
```

Exception result:

```raku
{
  type      => 37,      # MT_InvokeResult
  id        => $given-request-id,
  crashed   => True,
  kind      => "obj",
  handle    => $handle,    # e.g. 1256
  obj_type  => "X::AdHoc",
  concrete  => True,
  container => False
}
```

### Unhandled Exception (38)

Unsollicited response when an unhandled exception occurs.

All threads will be suspended. A handle to the exception object is included in the `handle` key, together with the thread ID it occurred on and the stack trace of that thread.

The `frames` key contains an array of hashes with information of each frame, similar to the "Stack Trace" response.

The VM is expected toi still allow operations such as introspecting the context, decontainerizing values, and invoking code.

```raku
{
  type   => 38,         # MT_UnhandledException
  id     => $given-request-id,
  thread => $thread-id, # e.g. 1
  handle => $handle,    # 1278,
  frames => [
    {
      file          => "path/to/source/file",
      line          => 22,
      bytecode_file => "path/to/bytecode/file",
      name => "some-method",
      type => "Method"
    },
    {
      file          => "path/to/source/file",
      line          => 12,
      bytecode_file => "path/to/bytecode/file",
      name          => "",
      type          => "Block"
    }
  ]
}
```

### Object Metadata Request (40)

Request additional (meta-)information about an object (by its handle) that goes beyond its actual attributes, followed by a "Object Metadata" response.

Can include miscellaneous details from the REPRData and the object's internal state if it's concrete.

Additionally, all objects that have positional, associative, or attribute features will point that out in their response.

```raku
{
  type   => 40,         # MT_ObjectMetadataRequest
  id     => $new-request-id,
  handle => $handle     # e.g 1345
}
```

### Object Metadata Response (41)

Response to an "Object Metadata" request, with the results in the `metadata` key (which contains a hash).

The `reprname` key contains name of the REPR.

All concrete objects have `size` and `unmanaged_size` keys (in bytes).

The `positional_elems` and `associative_elems` keys contain the number of elements for objects that have `Positional` and/or associative features.

The `pos_features`, `ass_features`, and `attr_features` keys indicate which of the "Object Positionals Request (42)", "Object Associatives Request (44)"), or "Object Attributes Request (32)" will give useful results.

```raku
{
  type     => 41,       # MT_ObjectMetadataResponse
  id       => $given-request-id,
  metadata => {
    reprname       => "VMArray",
    size           => 128,
    unmanaged_size => 1024,

    vmarray_slot_type => "num32",
    vmarray_elem_size => 4,
    vmarray_allocated => 128,
    vmarray_start     => 40,

    positional_elems => 12,

    pos_features  => $pos_features,  # True or False
    ass_features  => $ass_features,  # True or False
    attr_features => $attr_features  # True or False
  }
}
```

### Object Positionals Request (42)

Request to obtain information about a `Positional` object (such as an array) indicated by its handle, followed by an "Object Positionals" response.

```raku
{
  type   => 42,         # MT_ObjectPositionalsRequest
  id     => $new-request-id,
  handle => $handle     # e.g. 12345
}
```

### Object Positionals Response (43)

Response to an "Object Positionals" request, with the `contents` key containing a list of native values, or a list of hashes.

The `kind` key contains "int", "num", "str" for native arrays, or "obj" for object arrays.

In the case of an object array, every hash contains `type`, `handle`, `concrete`, and `container` keys, just as in the "Context Lexicals" response.

Native contents:

```raku
{
  type     => 43,       # MT_ObjectPositionalsResponse
  id       => $given-request-id,
  kind     => "int",
  start    => 0,
  contents => [
    1, 2, 3, 4, 5, 6
  ]
}
```

Object contents:

```raku
{
  type     => 43,       # MT_ObjectPositionalsResponse
  id       => $id,
  kind     => "obj",
  start    => 0,
  contents => [
    {
      type      => "Potato",
      handle    => $handle,  # e.g. 9999
      concrete  => True,
      container => False
    },
    {
      type      => "Noodles",
      handle    => $handle,  # e.g. 10000
      concrete  => False,
      container => False
    }
  ]
}
```

### Object Associatives Request (44)

Request to obtain information about a `Associative` object (such as a hash) indicated by its handle, followed by an "Object Associatives" response.

```raku
{
  type   => 44,         # MT_ObjectAssociativesRequest
  id     => $new-request-id,
  handle => $handle  # e.g. 12376
}
```

### Object Associatives Response (45)

Response to an "Object Associatives" request, with the `contents` key containing a hash of hashes always containing information about objects (so no native values).

The key is the key as used in the `Associative` object, and the value contains `type`, `handle`, `concrete`, and `container` keys, just as in the "Context Lexicals" response.

```raku
{
  type     => 45,       # MT_ObjectAssociativesResponse
  id       => $given-request-id,
  kind     => "obj"
  contents => {
    "Hello" => {
      type      => "Poodle",
      handle    => $handle,    # e.g. 4242
      concrete  => $concrete,  # True or False
      container => $container  # True or False
    },
    "Goodbye" => {
      type      => "Poodle",
      handle    => $handle,    # e.g. 4243
      concrete  => $concrete,  # True or False
      container => $container  # True or False
    }
  }
}
```

### Handle Equivalence Request (46)

Request to check a given list of handles (in the `handles` key) to see whether they refer to the same object, followed by a "Handle Equivalence" response.

```raku
{
  type    => 46,        # MT_HandleEquivalenceRequest
  id      => $new-request-id,
  handles => @handles
}
```

### Handle Equivalence Response (47)

Response to a "Handle Equivalence" request.

The `classes` key contains a list of lists with handles, in which each inner list contains the ID's of handles that refer to the same object (if there are more than one).

```raku
{
  type    => 47,        # MT_HandleEquivalenceResponse
  id      => $given-request-id,
  classes => [
    [1, 3],
    [2, 5, 7]
  ]
}
```

### HLL Symbol Request (48)

MoarVM features a mechanism for objects and types to be registered with an HLL, for example "nqp" or "Raku". This request allows you to find the available HLLs, a given HLL's keys, and the value for a given key.

Get all HLL names, followed by a "HLL Symbol" response:

```raku
{
  type => 48,           # MT_HLLSymbolRequest
  id   => $new-request-id,
}
```

Get an HLL's symbol names, followed by a "HLL Symbol" response:

```raku
{
  type => 48,           # MT_HLLSymbolRequest
  id   => $new-request-id,
  HLL  => $HLL          # e.g. "nqp" or "Raku"
}
```

Get the value for a symbol in a HLL, followed by a "Handle Result" response:

```raku
{
  type => 48,           # MT_HLLSymbolRequest
  id   => $new-request-id,
  HLL  => $HLL          # e.g. "nqp" or "Raku"
  name => "FOOBAR"
}
```

### HLL Symbol Response (49)

Response to a "HLL Symbol" request for names (rather than values).

The `keys` key contains either a list of HLL names, or a list of names for a given HLL.

```raku
{
  type => 49,
  id   => $given-request-id,
  keys => [
    "one",
    "two",
  ]
}
```

### Loaded Files Request (50)

In order to reliably set breakpoints, the filename supplied to the breakpoint command needs to match what is in the annotation exactly.

This command allows a debug client to ask what file names have been seen so far.

With the "start_watching" key set to True, notifications when a new filename is seen will be sent with File Loaded Notification type and the id of this request.

With "suspend", the thread that first encounters the new filename will suspend itself.

With "stacktrace", the notifications will also immediately send a stacktrace along for the thread that encounters the new file.

```raku
{
    type           => 50,
    id             => $new-request-id,
    start_watching => True,
    suspend        => False,
    stacktrace     => False,
}
```

### File Loaded Notification (51)

Response to a Loaded Files Request, as well as notification when new files show up later on.

Filename entries that were created not from a corresponding annotation being encountered but from requesting a breakpoint to be installed will have the "pending" key in addition to the "path" key.

In the notification, there may be a `full_path` key in the objects in the filenames array. This happens for files from a module where moarvm will strip off anything starting at the space and parenthesis for the purposes of what filename you need to pass to set a breakpoint. The `full_path` key will give the path including the parenthesised part, so that it can be displayed to the user, but setting a breakpoint on the `full_path` will not result in the breakpoint being hit.

Creating a file by requesting a breakpoint does not cause a notification to be sent out, but the same file later being encountered will cause such a notification.

Initial response:

```raku
{
    type      => 51,
    id        => $new-request-id,
    filenames => [
        { path => "src/vm/moar/ModuleLoader.nqp" },
        { path => "gen/moar/CORE.c.setting" },
        { path => "NQP::src/how/Archetypes.nqp" },
        { path => "SETTING::src/core.c/List.rakumod" },
        {
            path    => "lib/ACME/Foobar.rakumod",
            pending => True
        },
    ]
}
```

Notification:

```raku
{
    type      => 51,
    id        => $given-request-id,
    thread    => 1,
    filenames => [
        { path => "src/Perl6/Metamodel/PrivateMethodContainer.nqp" },
    ],
    frames    => [ ... ]
}
```

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

AUTHOR
======

  * Timo Paulssen

  * Raku Community

COPYRIGHT AND LICENSE
=====================

Copyright 2011 - 2020 Timo Paulssen

Copyright 2021 - 2025 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

