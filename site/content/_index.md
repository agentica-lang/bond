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

The guide describes Bond 0.5.0, which adds sessions, the cross-site check, `Bond.escape` with the EAG directive, the views guide, [WebSockets](/guide/websockets/) and [file uploads](/guide/uploads/) to 0.4.0.

- [Getting started](/getting-started/) installs Bond and runs a first app.
- The [guide](/guide/) has a page for each part.
- The source and the changelog are [on GitHub](https://github.com/agentica-lang/bond).

Bond needs Agentica 0.22.0 or later (the changelog has the version each release needs), and is under the Apache License 2.0.
