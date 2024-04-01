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

AUTHOR
======

Timo Paulssen

COPYRIGHT AND LICENSE
=====================

Copyright 2011 - 2020 Timo Paulssen

Copyright 2021 - 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

