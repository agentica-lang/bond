---
title: Conn and helpers
weight: 2
description: The Conn struct and the helpers that build an answer.
---

# Conn and helpers

`Bond.Conn` is an immutable struct. It holds the request: `method`, `path`, `query` (the raw text after `?`), `params`, `headers` (names in lowercase) and `body` (the `Bytes` that the client sent). It also holds the answer being built: `status` (200 at first), `response_headers`, `response_body` (`Bytes` too), `response_stream` (see [Streaming](/guide/streaming/)) and `halted`.

Every helper returns a new `Conn`, so a handler ends with `ok(Bond.text(conn, 200, "hello"))` and a helper can wrap another.

| Function | Does |
|---|---|
| `Bond.text(conn, status, text)` | answers plain text; sets `Content-Type`, so call `header` after it for another |
| `Bond.html(conn, status, text)` | answers HTML; sets `Content-Type`; does not escape the text |
| `Bond.escape(text)` | escapes `&`, `<`, `>`, `"` and `'` for HTML; see [HTML and escaping](/guide/escaping/) |
| `Bond.bytes(conn, status, body)` | answers `Bytes` as they are (an image, a download); sets `Content-Type` to `application/octet-stream`, so call `header` after it for the real type |
| `Bond.json(conn, status, value)` | answers `value` (a `Json`, such as `JSON.from(todos)` for a list or a map) as JSON; sets `Content-Type` |
| `Bond.json_as(conn, status, codec, value)` | answers a struct as JSON with its codec (`JSON.codec(Todo)`); sets `Content-Type`; see [JSON bodies](/guide/json/) |
| `Bond.status(conn, code)` | sets the status and nothing else |
| `Bond.redirect(conn, location)` | answers a 302 (or the status of a third argument) with `Location` and halts; see [Redirects](#redirects) |
| `Bond.halt(conn, status, text)` | answers plain text and stops the filters and the handler that come after |
| `Bond.header(conn, name, value)` | sets a response header |
| `Bond.body_text(conn)` | the body of the request as text, as a `Result[String]`, in the `charset` of the request (UTF-8 when it has none; UTF-16, UTF-32, ASCII, Latin-1, ISO-8859-15 and Windows-1252 too); a `charset` or a body that does not decode is a 400 |
| `Bond.request_header(conn, name)` | the first value of a request header, as a `Result[String]` |
| `Bond.param(conn, name)` | the text of a `:name` segment, as a `Result[String]` |
| `Bond.param_int(conn, name)` | the same, as a whole number; text that is not one is a 400 |
| `Bond.query(conn, name)` | the first value of `name` in the query string, decoded, as a `Result`; `Bond.query_int` is a whole number, `Bond.query_all` every value (`Result[List[String]]`), `Bond.query_params(conn)` the whole string decoded once (`Result[Map[String, List[String]]]`); see [Query and forms](/guide/query/) |
| `Bond.form(conn, name)` | the first value of a field of a form body, as a `Result`; `Bond.form_int`, `Bond.form_all` and `Bond.form_params(conn)` are like the `query` ones |
| `Bond.cookies(conn)` | the `Cookie` header read into a map; `Bond.cookie(conn, name)` is one value, as a `Result`; see [Cookies](/guide/cookies/) |
| `Bond.set_cookie(conn, name, value)` | adds a `Set-Cookie` as a `Result[Conn]`; `Bond.set_cookie_with(conn, cookie)` takes a `Cookie.Cookie`; `Bond.delete_cookie(conn, name)` deletes one |
| `Bond.send_file(conn, path, some(name))` | answers with a file read in pieces, with ranges; a name as `attachment` makes it a download; see [Sending files](/guide/files/) |
| `Bond.static(app, prefix, root)` | serves the files of a folder under a path; an app function, not a `Conn` one; see [Static files](/guide/static/) |
| `Bond.json_body(conn, codec)` | the body of the request decoded into a struct, as a `Result`; see [JSON bodies](/guide/json/) |
| `Bond.bad_request(message)` | an `error` that makes a 400 with `message` as its body |

## Redirects

`Bond.redirect` answers a 302, or the status you pass as the third argument: 301, 303, 307 or 308 (any other is a runtime error in the handler, so a 500). It sets `Location`, clears the body and the content type and halts, so a `before` filter can use it. `Location` must be ASCII: percent-encode anything else, or the answer is a 500. `Bond.redirect` does not check the target (`//evil.com`, `/\evil.com` and `javascript:` pass through), so a redirect to an address that a client gave (`?next=...`) is an open redirect unless you check it first: the rule and a sample are in [HTML and escaping](/guide/escaping/).

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

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/old", &old_page)
    |> Bond.get("/new", &new_page)
  )
  moved = Testing.request(app, "GET", "/old")
  puts("#{moved.status} #{HTTP.header_values(moved.headers, "location")[0]}")
  puts(Testing.text(Testing.request(app, "GET", "/new")).unwrap!)
end
```

```output
301 /new
<p>the new page</p>
```
