---
title: Running and options
weight: 12
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

`Bond.run_with(app, host, port, options)` and `Bond.start_with(app, host, port, options)` take the options of the server of `std/http`. `HTTP.ServerOptions` has `request_timeout_ms`, `idle_timeout_ms`, `max_connections` and `max_body_bytes`. Every field has a default, so `HTTP.ServerOptions(max_body_bytes: 4_194_304)` changes one field and keeps the rest. The other functions use `HTTP.ServerOptions()`.

The `before` filters and the route lookup run on the head of the request alone. Bond reads the body, whole as `Conn` holds it as bytes, only when the request goes on to its handler: a request that a filter halts, or that has no route for its path or method, is answered without the body (the connection closes after the answer when the body has not arrived), so a client that declared a body and never sends it gets its 401, 404 or 405 at once. A refused body is answered like the server of `std/http` answers it, and the handler is not called: a body over `max_body_bytes` is a 413, a chunk line that is too long a 431 and a bad chunk a 400, all with `Connection: close`. A client that leaves before the body is whole gets no answer.
