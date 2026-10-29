---
title: Conn and helpers
weight: 2
description: The Conn struct and the helpers that build an answer.
---

# Conn and helpers

`Bond.Conn` is an immutable struct. It holds the request: `method`, `path`, `query` (the raw text after `?`), `params`, `headers` (names in lowercase) and `body`. It also holds the answer being built: `status` (200 at first), `response_headers`, `response_body` and `halted`.

Every helper returns a new `Conn`, so a handler ends with `ok(Bond.text(conn, 200, "hello"))` and a helper can wrap another.

| Function | Does |
|---|---|
| `Bond.text(conn, status, text)` | answers plain text; sets `Content-Type`, so call `header` after it for another |
| `Bond.html(conn, status, text)` | answers HTML; sets `Content-Type`; does not escape the text |
| `Bond.json(conn, status, value)` | answers `value` (a `Json`, such as `JSON.from(todo)`) as JSON; sets `Content-Type` |
| `Bond.status(conn, code)` | sets the status and nothing else |
| `Bond.redirect(conn, location)` | answers a 302 with a `Location` header, no body and no `Content-Type`, and halts; a third argument gives 301, 303, 307 or 308, and any other code is a runtime error, so a 500 |
| `Bond.halt(conn, status, text)` | answers plain text and stops the filters and the handler that come after |
| `Bond.header(conn, name, value)` | sets a response header |
| `Bond.request_header(conn, name)` | the first value of a request header, as a `Result[String]` |
| `Bond.param(conn, name)` | the text of a `:name` segment, as a `Result[String]` |
| `Bond.param_int(conn, name)` | the same, as a whole number; text that is not one is a 400 |
| `Bond.query(conn, name)` | the first value of `name` in the query string, decoded, as a `Result`; see [Query and forms](/guide/query/) |
| `Bond.query_int(conn, name)` | the same, as a whole number; text that is not one is a 400 |
| `Bond.query_all(conn, name)` | every value of `name`, in order, as a `Result[List[String]]` |
| `Bond.query_params(conn)` | the whole query string decoded once, as a `Result[Map[String, List[String]]]` |
| `Bond.form(conn, name)` | the first value of a field of a form body, decoded, as a `Result` |
| `Bond.form_int(conn, name)` | the same, as a whole number |
| `Bond.form_all(conn, name)` | every value of a field, in order |
| `Bond.form_params(conn)` | the whole form body decoded once, like `query_params` |
| `Bond.json_body(conn, codec)` | the body of the request decoded into a struct, as a `Result`; see [JSON bodies](/guide/json/) |
| `Bond.bad_request(message)` | an `error` that makes a 400 with `message` as its body |

## HTML and escaping

`Bond.html` sends the text as it is. Bond has no HTML escaping yet, so escape what a client sent before you put it in the text.

## Redirects

`Bond.redirect` answers a 302, or the status you pass as the third argument: 301, 303, 307 or 308. It sets `Location`, clears the body and the content type and halts, so a `before` filter can use it. Any other status is a runtime error in the handler, so a 500. `Location` must be ASCII: percent-encode anything else, or the answer is a 500. A redirect to an address built from client input is an open redirect: check it first.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def old_page(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/new", 301))
end

def new_page(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 200, "<p>the new page</p>"))
end

def not_a_redirect(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/new", 200))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/old", &old_page)
    |> Bond.get("/new", &new_page)
    |> Bond.get("/wrong", &not_a_redirect)
  )
  moved = Testing.request(app, "GET", "/old", [], "")
  puts("#{moved.status} #{HTTP.header_values(moved.headers, "location")[0]}")
  puts(Testing.request(app, "GET", "/new", [], "").body)
  puts(Testing.request(app, "GET", "/wrong", [], "").status)
end
```

```output
301 /new
<p>the new page</p>
500
```

## Bad requests

`Bond.bad_request(message)` gives an `error` that makes a 400 with `message` as its body. `Bond.param_int` uses it for text that is not a number.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def create(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.body.empty?
    return Bond.bad_request("title is empty")
  end

  return ok(Bond.text(conn, 201, "created #{conn.body}"))
end

def main() -> Void
  app = Bond.app() |> Bond.post("/todos", &create)
  empty = Testing.request(app, "POST", "/todos", [], "")
  puts("#{empty.status} #{empty.body}")
end
```

```output
400 title is empty
```
