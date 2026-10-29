## The cookies of a request and of a response, read and written with `std/cookie`.

import C from "std/cookie"
import Conns from "conn"
import {Conn} from "conn"

# The date of a deleted cookie, for the clients that ignore Max-Age.
EPOCH = "Thu, 01 Jan 1970 00:00:00 GMT"

## The `Cookie` header of the request read into a map from name to value: the first value of a name wins, and the
## values are as the client sent them (not decoded). More than one `Cookie` header is read as one. Read it once and
## take the cookies from the map when a handler needs several.
export def cookies(conn: Conn) -> Map[String, String]
  sent = conn.headers.select do |field| field.name.downcase == "cookie" end
  return C.parse(sent.map do |field| field.value end.join("; "))
end

## The value of a cookie of the request, or an error when it is not there. A missing cookie is not a mistake of the
## client (a first visit has none), so it is a plain `error`, which is a 500 if a handler passes it on with `try`:
## use `unwrap_or` or `case`.
export def cookie(conn: Conn, name: String) -> Result[String]
  case cookies(conn).get(name)
    ok(value) -> return ok(value)
    error(_) -> return error("no cookie #{name}")
  end
end

## Adds a `Set-Cookie` header with the defaults of Bond: `Path=/` (so the cookie is not tied to the folder of the
## request), `HttpOnly` (scripts cannot read it) and `SameSite=Lax` (it is not sent with a cross-site POST). It has
## no `Secure`, since Bond cannot tell if the site is on HTTPS and a `Secure` cookie is dropped over plain HTTP: set
## it with `set_cookie_with` in production. The cookie lasts until the browser closes. `value` is written as it is:
## a space, a comma, a semicolon, a quote or a non-ASCII character in it is an `error` (a 500 when passed on with
## `try`), so encode it first.
export def set_cookie(conn: Conn, name: String, value: String) -> Result[Conn]
  return set_cookie_with(conn, C.Cookie(name: name, value: value, path: "/", http_only: true, same_site: "Lax"))
end

## Adds a `Set-Cookie` header for a `Cookie.Cookie` of `std/cookie` (`import Cookie from "std/cookie"`), with the
## attributes `path`, `domain`, `max_age`, `expires`, `secure`, `http_only` and `same_site` that you give: Bond adds
## none. Each cookie is a header of its own, never joined with another. The `error` of `std/cookie` for a name or
## value it refuses is passed on. Set a cookie once: the headers are not merged by name.
export def set_cookie_with(conn: Conn, cookie: C.Cookie) -> Result[Conn]
  case C.set_header(cookie)
    ok(line) -> return ok(Conns.add_header(conn, "set-cookie", line))
    error(message) -> return error("cookie: #{message}")
  end
end

## Deletes a cookie: a `Set-Cookie` header with `Max-Age=0` and a date in the past. `path` and `domain` must be the
## ones the cookie was set with (`set_cookie` uses `/` and no domain). A name that starts with `__Host-` or
## `__Secure-` is written with `Secure`, which browsers need to accept it.
export def delete_cookie(conn: Conn, name: String, path: String = "/", domain: String = "") -> Result[Conn]
  prefix = name.downcase
  secure = prefix.start_with?("__host-") or prefix.start_with?("__secure-")
  gone = C.Cookie(name: name, value: "", path: path, domain: domain, max_age: 0, expires: EPOCH, secure: secure)
  return set_cookie_with(conn, gone)
end
