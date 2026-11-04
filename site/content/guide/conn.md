---
title: Conn and helpers
weight: 2
description: The Conn struct and the helpers that build an answer.
---

# Conn and helpers

`Bond.Conn` is an immutable struct. It holds the request: `method`, `path`, `query` (the raw text after `?`), `params`, `headers` (names in lowercase), `body` (the `Bytes` that the client sent) and `remote_addr` (the IP address of the client, see [Client address](#client-address)). It also holds the answer being built: `status` (200 at first), `response_headers`, `response_body` (`Bytes` too), `response_stream` (see [Streaming](/guide/streaming/)) and `halted`. `assigns` holds the values that a filter keeps for the handler (see [Assigns](#assigns)).

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
| `Bond.set_cookie(conn, name, value)` | adds a `Set-Cookie` (`Path=/`, `HttpOnly`, `SameSite=Lax`) as a `Result[Conn]`; `Bond.set_cookie_with(conn, cookie)` takes a `Cookie.Cookie` with every attribute; `Bond.delete_cookie(conn, name)` deletes one; see [Cookies](/guide/cookies/) |
| `Bond.send_file(conn, path, some(name))` | answers with a file read in pieces, with ranges; a name as `attachment` makes it a download; see [Sending files](/guide/files/) |
| `Bond.static(app, prefix, root)` | serves the files of a folder under a path; an app function, not a `Conn` one; see [Static files](/guide/static/) |
| `Bond.json_body(conn, codec)` | the body of the request decoded into a struct, as a `Result`; see [JSON bodies](/guide/json/) |
| `Bond.assign(conn, key, value)` | keeps a value of the request for the filters and the handler that come after; see [Assigns](#assigns) |
| `Bond.assigned(conn, key, codec)` | the value kept under `key`, as the type of the codec (`JSON.codec(Person)`), as a `Result`; `Bond.assigned?(conn, key)` asks whether there is one |
| `Bond.bad_request(message)` | an `error` that makes a 400 with `message` as its body |

## Client address

`conn.remote_addr` is the IP address of the peer that opened the connection, with no port (`"127.0.0.1"`, `"::1"`), as the server of `std/http` fills `HttpRequest.remote_addr` (Agentica 0.22.0 or later). It is `""` in a `Conn` that you build by hand without it.

Behind a proxy or a load balancer, it is the address of the proxy, not of the visitor. Bond does not read `X-Forwarded-For` or `Forwarded`: any client can send them, so trusting them by default would let a visitor choose its own address. If your proxy sets one, read it with `Bond.request_header(conn, "x-forwarded-for")` and use it only when the request came from your proxy.

`Testing.request` gives the handler `"127.0.0.1"` (`Testing.LOOPBACK`); `Testing.request_from(app, "203.0.113.9", "GET", "/")` chooses another (see [Testing](/guide/testing/)).

## Assigns

A filter often looks something up that the handler needs too, such as the signed-in person. `Bond.assign(conn, key, value)` keeps a value in the `Conn` under a name, and `Bond.assigned(conn, key, codec)` reads it back as a `Result` of the type of the codec, so the handler does not look it up again. The values live as long as the request and are never sent to the client.

`Conn` has no type parameter: a value is kept as the `Json` of `JSON.from(value)`, and the reader names its type with a codec, as in [JSON bodies](/guide/json/). Anything that `JSON.encode` takes can be assigned (a struct, a list, a map with `String` keys, an `Optional`, a number, text); a `Fn`, `Bytes` or `Task` is refused by the checker at the `Bond.assign` call. A value comes back as a copy of what was assigned, so the reader needs a type with the same fields. Keep the lookup result small: an id and a name, not a whole table row.

`Bond.assigned` is an `error` when nothing was assigned under the key and when the value is not of the type of the codec. Both are mistakes of the program, not of the client, so a handler that uses `try` answers a 500. A filter that may or may not find a person assigns only when it did, and a handler that allows both asks with `Bond.assigned?` first.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

struct Person
  id: Int
  name: String
end

# The sign-in check: the only place that looks the person up.
def sign_in(conn: Bond.Conn) -> Result[Bond.Conn]
  case Bond.request_header(conn, "x-user")
    ok(name) -> return ok(Bond.assign(conn, "person", Person(id: 7, name: name)))
    error(_) -> return ok(Bond.halt(conn, 401, "sign in"))
  end
end

def room(conn: Bond.Conn) -> Result[Bond.Conn]
  person = try Bond.assigned(conn, "person", JSON.codec(Person))
  return ok(Bond.text(conn, 200, "#{person.name} (#{person.id}) is in the room"))
end

def main() -> Void
  app = Bond.app() |> Bond.before(&sign_in) |> Bond.get("/room", &room)
  headers = [Header(name: "x-user", value: "ana")]
  puts(Testing.text(Testing.request(app, "GET", "/room", headers)).unwrap!)
  puts(Testing.request(app, "GET", "/room").status)
end
```

```output
ana (7) is in the room
401
```

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
