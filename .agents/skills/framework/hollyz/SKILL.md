---
name: holyz-framework
description: This skill should be used when designing or generating HolyZ Framework syntax. HolyZ is a compact, HolyC-inspired framework syntax and DSL design that can be implemented in any programming language. Use this skill for HolyZ syntax, declarations, components, routing, state, configuration, APIs, and framework DSL design.
---
# HolyZ Framework

## Introduction

HolyZ is a framework syntax design, not a programming language.

It defines a compact, C/HolyC-inspired syntax layer that can be implemented, transpiled, or interpreted by any programming language.

HolyZ focuses on:

- Compact syntax
- Explicit declarations
- Framework DSLs
- Components
- Routing
- State
- Configuration
- Metadata
- Events
- Services
- Extensible syntax

The underlying implementation language is independent of HolyZ.

---

## Design Philosophy

HolyZ syntax should be:

- **Compact** — minimal boilerplate.
- **Readable** — syntax should be understandable without framework-specific noise.
- **Declarative** — describe what an application contains and does.
- **Language-independent** — syntax must not depend on C, Rust, Go, TypeScript, Python, or another implementation language.
- **Extensible** — frameworks can define additional keywords and constructs.
- **HolyC-inspired** — braces, semicolons, compact declarations, and C-like expressions are preferred.

---

## Basic Syntax

Blocks use braces:

```
Thing Name
{
    ...
};
```

Statements normally end with `;`.

Expressions use familiar operators:

```
+  -  *  /  %
== != < > <= >=
&& || !
= += -= *= /=
```

---

## Declarations

Generic declaration:

```
type Name
{
    field;
    field;
};
```

Example:

```
model User
{
    id;
    name;
    email;
};
```

---

## Types

HolyZ does not mandate an implementation type system. A framework may define:

```
I32   I64
U32   U64
F32   F64
Bool  Str
```

or map HolyZ types to the host language. For example:

```
User user;
List<User> users;
```

The host implementation decides how these types are represented.

---

## Functions

Function syntax:

```
fn Name(args)
{
    ...
}
```

Example:

```
fn Add(a, b)
{
    return a + b;
}
```

Typed syntax may be used when the target framework supports it:

```
I64 Add(I64 a, I64 b)
{
    return a + b;
}
```

---

## Modules

```
module Graphics;

import Math;
import Network;
```

---

## Components

Components provide a reusable UI/application unit:

```
component Counter
{
    state count = 0;

    view
    {
        Button("+", => Increment);
        Text($"Count: {count}");
    }

    fn Increment()
    {
        count++;
    }
};
```

The host framework determines how the component is rendered.

---

## State

State declaration:

```
state count = 0;
```

Reactive observation:

```
watch count
{
    UpdateView();
}
```

The implementation language/framework decides how reactivity works.

---

## Events

Event handlers use compact arrow syntax:

```
Button("Save", => Save);
```

Events may also be declared explicitly:

```
event OnSave;
```

---

## Routing

HTTP or application routing:

```
app API
{
    GET "/" => Home;
    GET "/users/:id" => GetUser;
    POST "/users" => CreateUser;
};
```

The syntax describes the route; the host framework determines the networking implementation.

---

## Metadata

Attributes use `@`:

```
@Entity("users")
@Auth("admin")
model User
{
    @PrimaryKey
    id;

    name;
};
```

Attributes are framework-defined metadata.

---

## Configuration

```
config Server
{
    host = "0.0.0.0";
    port = 8080;
    debug = true;
};
```

---

## Services

```
service Database
{
    connect = "postgres://...";
};

service Cache
{
    driver = "redis";
};
```

The actual implementation is determined by the host framework.

---

## Generic DSL Pattern

HolyZ can define framework-specific constructs without requiring a specific runtime:

```
feature Authentication
{
    provider = "jwt";

    login "/login" => Login;
    logout "/logout" => Logout;
};
```

---

## Implementation Independence

HolyZ syntax may be implemented using:

```
HolyZ
  ↓
Parser / Compiler / Interpreter
  ↓
Host Language
  ├── C
  ├── C++
  ├── Rust
  ├── Go
  ├── TypeScript
  ├── Python
  ├── Java
  └── Any suitable language
```

Do not assume that HolyZ code directly executes as a native programming language.

---

## Code Generation Guidelines

When generating HolyZ:

1. Keep syntax compact.
2. Prefer braces and semicolons.
3. Use C/HolyC-inspired declarations.
4. Keep framework constructs declarative.
5. Do not assume a specific implementation language.
6. Do not introduce language-specific runtime behavior unless requested.
7. Separate HolyZ syntax from its host-language implementation.
8. Framework-specific keywords should be simple and composable.
9. Prefer syntax that can be parsed into an AST and transformed into another language.

---

## Core Rule

> **HolyZ defines the syntax. The host language defines the implementation.**

When answering HolyZ questions, focus on syntax and framework semantics rather than assuming HolyZ itself is a standalone programming language.
