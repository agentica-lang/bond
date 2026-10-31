---
title: Bond
description: Bond is a small web framework for Agentica, in the spirit of Sinatra.
---

Bond is a small web framework for [Agentica](https://agentica-lang.github.io/agentica/), in the spirit of Sinatra. You add routes to an app, the app is an immutable value, and a handler is a function from a `Conn` to a `Result[Conn]`.

```agentica
import Bond from "pkg/bond/bond"

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/hello", &hello)
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

Bond 0.3.0 has the router, filters, custom `not_found` and `on_error` handlers, JSON request bodies, query strings and forms, cookies, static files (any file, as bytes), streamed bodies (server-sent events), a guide to HTML escaping, the helpers to answer, server options and `Testing.request`, which runs an app in process with no socket. WebSockets come later (see [the design](https://github.com/agentica-lang/bond/issues/1)).

- [Getting started](/getting-started/) installs Bond and runs a first app.
- The [guide](/guide/) has a page for each part.
- The source and the changelog are [on GitHub](https://github.com/agentica-lang/bond).

Bond needs Agentica 0.19.0-beta.3 or later, and is under the Apache License 2.0.
