---
title: Testing
weight: 13
description: Run an app in process with Testing.request, with no socket.
---

# Testing

`Testing.request` runs an app in process, with no socket, through the same filters and routes as `Bond.run`. Import it from `pkg/bond/testing`.

Its arguments are the app, the method, the path (with its query, if any), and the request headers and the body, which are optional: `Testing.request(app, "GET", "/hello")` sends no headers and an empty body. It gives an `HttpResponse` with `status`, `headers` and `body`, which is `Bytes`: `Testing.text(response)` reads it as text, as a `Result[String]`. A request body that is not text goes in `Testing.request_bytes(app, method, path, headers, body)`, which takes the body as `Bytes` (so the headers come first and have no default). A response the server would refuse is a 500 here too, so a test sees what a client would. A `HEAD` request is answered with the body of a whole answer, which the server would drop (a streamed or sent file has none). A streamed body (below) is read to its end, and the pieces are the body.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  response = Testing.request(app, "GET", "/hello")
  puts("#{response.status} #{Testing.text(response).unwrap!}")
end
```

```output
200 hello
```

`Testing.request` builds an `HttpRequest` and passes it to `Bond.handle(app, request)`, which is the whole-response form of what `Bond.run` calls for each request that comes over the socket (`Bond.handle_stream`, which gives an `HTTP.StreamResponse`). Call `Bond.handle` yourself when you already have an `HttpRequest`: it gives the `HttpResponse`.

For a streamed body (see [Streaming](/guide/streaming/)), two optional arguments after the body bound the wait for the end of the stream: `max_pieces` (0, the default, is no limit) closes the channel after that many pieces, and `timeout_ms` (10 s by default) is the time for the whole body, so one gap between pieces may take all of it (`timeout_ms: 30_000` allows a 20 s gap). Either one closes the channel, so a producer that never ends stops, and a body cut by the time says so on stderr.
