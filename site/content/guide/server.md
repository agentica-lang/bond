---
title: Running and options
weight: 8
description: Bond.run, Bond.start and the options of the HTTP server.
---

# Running and options

`Bond.run(app, host, port)` serves the app with the HTTP server of `std/http` and returns when it closes. `Bond.start(app, host, port)` returns the server at once. With port 0 it picks a free port, and `Bond.local_port(server)` says which. `Bond.wait(server)` waits for it and `Bond.stop(server)` closes it.

The server belongs to the task that started it, so call it from `main`.

```agentica
import Bond from "pkg/bond/bond"

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/hello", &hello)
  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  Bond.wait(server).unwrap!
end
```

## Options

`Bond.run_with(app, host, port, options)` and `Bond.start_with(app, host, port, options)` take the options of the server of `std/http`. `HttpServerOptions` has `request_timeout_ms`, `idle_timeout_ms`, `max_connections` and `max_body_bytes`. Start from `HTTP.server_options()` and change what you need with `.with`. The other functions use `HTTP.server_options()` as it is.

A body over `max_body_bytes` is a 413 from the server, and never reaches the app.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/hello", &hello)
  options = HTTP.server_options().with(max_body_bytes: 4_194_304, max_connections: 64)
  Bond.run_with(app, "127.0.0.1", 4567, options).unwrap!
end
```
