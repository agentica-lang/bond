---
title: Testing
weight: 11
description: Run an app in process with Testing.request, with no socket.
---

# Testing

`Testing.request` runs an app in process, with no socket, through the same filters and routes as `Bond.run`. Import it from `pkg/bond/testing`.

Its arguments are the app, the method, the path (with its query, if any), the request headers and the body. It gives an `HttpResponse` with `status`, `headers` and `body`. A response the server would refuse is a 500 here too, so a test sees what a client would. A `HEAD` request is answered with the body, which the server would drop.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  response = Testing.request(app, "GET", "/hello", [], "")
  puts("#{response.status} #{response.body}")
end
```

```output
200 hello
```

`Testing.request` builds an `HttpRequest` and passes it to `Bond.handle(app, request)`, which is what `Bond.run` calls for each request that comes over the socket. Call `Bond.handle` yourself when you already have an `HttpRequest`: it gives the `HttpResponse`.

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
