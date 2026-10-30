---
title: Testing
weight: 11
description: Run an app in process with Testing.request, with no socket.
---

# Testing

`Testing.request` runs an app in process, with no socket, through the same filters and routes as `Bond.run`. Import it from `pkg/bond/testing`.

Its arguments are the app, the method, the path (with its query, if any), and the request headers and the body, which are optional: `Testing.request(app, "GET", "/hello")` sends no headers and an empty body. It gives an `HttpResponse` with `status`, `headers` and `body`. A response the server would refuse is a 500 here too, so a test sees what a client would. A `HEAD` request is answered with the body, which the server would drop. A streamed body (see [Streaming](/guide/streaming/)) is read to its end, and the pieces are the body.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  response = Testing.request(app, "GET", "/hello")
  puts("#{response.status} #{response.body}")
end
```

```output
200 hello
```

`Testing.request` builds an `HttpRequest` and passes it to `Bond.handle(app, request)`, which is the whole-response form of what `Bond.run` calls for each request that comes over the socket (`Bond.handle_stream`, which gives an `HTTP.StreamResponse`). Call `Bond.handle` yourself when you already have an `HttpRequest`: it gives the `HttpResponse`.

A streamed body (see [Streaming](/guide/streaming/)) is read until the producer closes its channel, so a test sees all of it. Two optional arguments after the body bound it: `max_pieces` (0, the default, is no limit) closes the channel after that many pieces, and `timeout_ms` (10 s by default) is the time for the whole body. Either one closes the channel, so a producer that never ends stops, and a body cut by the time says so on stderr. Testing reads text streams only for now: a stream that is not UTF-8 is a 500 whose body is `the stream is not UTF-8 text` (an `HttpResponse` holds text). A `HEAD` gets no body, as over a socket.

```agentica
import Bond from "pkg/bond/bond"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  request = HttpRequest(method: "GET", target: "/hello", path: "/hello", headers: [], body: "")
  response = Bond.handle(app, request)
  puts("#{response.status} #{response.body}")
end
```

```output
200 hello
```

Bond tests itself this way. The behavior is a Gherkin scenario in `specs/*.feature`, run by `agentica test`, and the steps drive an app through `Testing.request`. Only `specs/server.feature` opens a socket, on 127.0.0.1 and a free port.
