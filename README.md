# MoarVM::Remote

A perl6 library to interface with MoarVM's remote debugger protocol.

It's mostly a thin layer above the wire format, documented in the moarvm repository under https://github.com/MoarVM/MoarVM/blob/master/docs/debug-server-protocol.md

It exposes commands as methods, responses as Promises, and events/event streams as Supplies.

You can use the debug protocol with the perl6 module/program App::MoarVM::Debug. Another application that supports the debug protocol is Comma, at commaide.com
