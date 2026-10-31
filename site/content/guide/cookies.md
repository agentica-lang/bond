---
title: Cookies
weight: 5
description: Read the cookies of a request and set or delete them in the answer, with std/cookie.
---

# Cookies

`Bond.cookies(conn)` reads the `Cookie` header into a `Map[String, String]`, with `std/cookie`. The first value of a name wins, and the values are as the client sent them: they are not decoded or unquoted. More than one `Cookie` header is read as one. A handler that needs several cookies reads the map once; `Bond.cookie(conn, "sid")` gives one value as a `Result`.

A cookie that is not there is an `error`, but a plain one, like `Bond.param` and `Bond.request_header`: a first visit has no cookie, and that is not a mistake of the client. This is different from `Bond.query`, where a missing name is a 400. So `try Bond.cookie(conn, "sid")` on a first visit is a 500: use `unwrap_or` or `case` and answer it yourself, for example with a redirect to the login page.

A value is as the client sent it, and `Bond.cookies` does not decode it. Encode a value with `URI.encode_www_form_component` (from `std/uri`) before you set it, and read it back with `URI.decode_www_form_component`.

## Setting a cookie

`Bond.set_cookie(conn, "sid", value)` adds a `Set-Cookie` header with the defaults that Bond chose:

- `Path=/`, so the cookie is not tied to the folder of the request that set it.
- `HttpOnly`, so scripts on the page cannot read it.
- `SameSite=Lax`, so the browser does not send it with a cross-site `POST`.
- No `Secure` and no `Max-Age`: Bond cannot tell if the site is served over HTTPS, and a `Secure` cookie is dropped over plain HTTP, which would break a program in development. The cookie lasts until the browser closes. Set `Secure` yourself in production, with `set_cookie_with`.

`Bond.set_cookie_with(conn, cookie)` takes a `Cookie.Cookie` of `std/cookie` (`import Cookie from "std/cookie"`) with the attributes you give: `path`, `domain`, `max_age`, `expires`, `secure`, `http_only` and `same_site`. Bond adds none of its own there, so write `http_only: true` and `same_site: "Lax"` when you want them.

Both give a `Result[Conn]`: use `try`. A name that is not a token, or a value with a space, a comma, a semicolon, a quote, a control or a non-ASCII character, is an `error` (a 500 when it is passed on), and no cookie is set. `std/cookie` never encodes or decodes, so a value that comes from a client must be encoded first, as above.

`set_cookie` has no other arguments: `set_cookie_with` covers `Secure` and `Max-Age`. In production, one cookie of a year, over HTTPS, is:

```agentica
import Cookie from "std/cookie"
import Bond from "pkg/bond/bond"

def remember(conn: Bond.Conn, id: String) -> Result[Bond.Conn]
  year = Cookie.Cookie(
    name: "sid",
    value: id,
    path: "/",
    max_age: 31_536_000,
    secure: true,
    http_only: true,
    same_site: "Lax",
  )
  return Bond.set_cookie_with(conn, year)
end
```

A name that starts with `__Host-` or `__Secure-` needs `secure: true`, so `set_cookie` always fails for it: use `set_cookie_with`. `__Host-` also needs `path: "/"` and no domain.

Each cookie is a header of its own: Bond never joins two `Set-Cookie` headers with a comma, and the HTTP server writes each one. `Bond.header(conn, "Set-Cookie", value)` is the one exception to "a header replaces the one of the same name": it adds a header too, so it never wipes the cookies set before it. Set a cookie once per answer, since the headers are not merged by name. A `before` filter can set a cookie and a later `Bond.redirect` keeps it. A 500 does not: it is a new answer with no header of the failed one.

## Deleting a cookie

`Bond.delete_cookie(conn, "sid")` writes a `Set-Cookie` with `Max-Age=0` and a date in the past. The browser matches a cookie by name, path and domain, so pass the `path` and `domain` it was set with: `Bond.delete_cookie(conn, "sid", "/app", "example.com")`. `set_cookie` uses `/` and no domain, as the default does. A name that starts with `__Host-` or `__Secure-` is deleted with `Secure`, which browsers need for those names.

```agentica
import Cookie from "std/cookie"
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def login(conn: Bond.Conn) -> Result[Bond.Conn]
  with_sid = try Bond.set_cookie(conn, "sid", "abc123")
  theme = Cookie.Cookie(name: "theme", value: "dark", max_age: 3600, secure: true, same_site: "Strict")
  with_theme = try Bond.set_cookie_with(with_sid, theme)
  return ok(Bond.text(with_theme, 200, "welcome"))
end

def whoami(conn: Bond.Conn) -> Result[Bond.Conn]
  sid = Bond.cookie(conn, "sid").unwrap_or("nobody")
  return ok(Bond.text(conn, 200, "hello #{sid}"))
end

def logout(conn: Bond.Conn) -> Result[Bond.Conn]
  gone = try Bond.delete_cookie(conn, "sid")
  return ok(Bond.text(gone, 200, "bye"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/login", &login)
    |> Bond.get("/whoami", &whoami)
    |> Bond.get("/logout", &logout)
  )
  for path in ["/login", "/logout"]
    response = Testing.request(app, "GET", path)
    for line in HTTP.header_values(response.headers, "set-cookie")
      puts(line)
    end
  end
  headers = [Header(name: "Cookie", value: "sid=abc123; theme=dark")]
  puts(Testing.text(Testing.request(app, "GET", "/whoami", headers)).unwrap!)
  puts(Testing.text(Testing.request(app, "GET", "/whoami")).unwrap!)
end
```

```output
sid=abc123; Path=/; HttpOnly; SameSite=Lax
theme=dark; Max-Age=3600; Secure; SameSite=Strict
sid=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT
hello abc123
hello nobody
```
