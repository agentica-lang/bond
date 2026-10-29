---
title: Errors
weight: 9
description: What a failure answers, and the not_found and on_error handlers.
---

# Errors

A handler or filter that gives `error(message)` makes a 500 with the body `Internal Server Error`. The message goes to stderr, never to the client. `Bond.bad_request(message)` is the error that makes a 400 with `message` as its body.

A runtime error in a handler or filter (an index out of range, an `unwrap!` of an error) is a 500 too, and does not stop the program. The request runs in a task of its own, and the crash of the task is the error. The VM prints the stack trace on stderr, and Bond adds one line with the method and the path. The `after` filters do not run for a crash.

A response that the HTTP server of `std/http` would refuse is a plain 500, with a warning on stderr. That is a status outside 200 to 599, a `Content-Length` or `Transfer-Encoding` header, a header name that is not an HTTP token, and a value with a control character or a character beyond Latin-1. A 204 or 304 loses its body.

## Custom handlers

They work like `not_found do ... end` and `error do ... end` of Sinatra.

The handlers are your code, so escape any value of the client that they put in HTML, `conn.path` included: see [HTML and escaping](/guide/escaping/). `Bond.not_found(app, handler)` answers a path with no route, in place of the plain `not found`. The handler is an ordinary `Bond.Handler`. It gets the `Conn` with the status 404, and the `after` filters run after it. It does not answer a 405, and not a 404 that a handler gives itself.

`Bond.on_error(app, handler)` answers a failure in place of the plain 500. The handler is a `Bond.ErrorHandler`, a `Fn[Bond.Conn, String, Result[Bond.Conn]]`: it takes the `Conn` and the message, and gives a `Result[Bond.Conn]`. It gets the request `Conn` with the status 500 and nothing of the answer built so far, and the message of the failure. Bond has already written the message to stderr, and nothing sends it to the client unless the handler does: keep it out of the answer.

If the error handler gives an `error` or crashes, the answer is the plain 500. It is never called for a `bad_request`, nor for a response that the server would refuse. Both handlers are set once per app; a second call replaces the first.

```agentica
import HTML from "std/html"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def broken(conn: Bond.Conn) -> Result[Bond.Conn]
  return error("the database is down")
end

def page_not_found(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 404, "<h1>Nothing at #{HTML.escape(conn.path)}</h1>"))
end

def page_failed(conn: Bond.Conn, message: String) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 500, "<h1>Something went wrong</h1>"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/broken", &broken)
    |> Bond.not_found(&page_not_found)
    |> Bond.on_error(&page_failed)
  )
  missing = Testing.request(app, "GET", "/nothing")
  puts("#{missing.status} #{missing.body}")
  failed = Testing.request(app, "GET", "/broken")
  puts("#{failed.status} #{failed.body}")
end
```

```output
404 <h1>Nothing at /nothing</h1>
500 <h1>Something went wrong</h1>
```
