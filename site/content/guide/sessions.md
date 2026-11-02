---
title: Sessions
weight: 6
description: Keep the data of a visitor in a signed cookie, with no store on the server.
---

# Sessions

`Bond.sessions(app, options)` keeps a small session in a cookie that Bond signs with HMAC-SHA256. There is no store on the server: the cookie holds the data, and the signature lets Bond see that the client did not change it. A handler reads and changes the session as a map of text:

- `Bond.session(conn)` is the session as a `Map[String, String]`, empty for a visitor with none.
- `Bond.get_session(conn, "user")` is one value, an `error` when it is not there (a plain one, like `Bond.cookie`: use `unwrap_or` or `case`).
- `Bond.set_session(conn, "user", "ana")`, `Bond.delete_session(conn, "user")` and `Bond.clear_session(conn)` give a new `Conn` with the session changed, as `Bond.status` does. Keep the `Conn` they return.

The answer carries the new session in a `Set-Cookie`, and only when a handler changed it: a request that only reads sets no cookie. An empty session after a change (`clear_session`, or the last value deleted) deletes the cookie.

## The options

`Bond.app() |> Bond.sessions(Bond.SessionOptions(secret: secret))` is the whole setup.

`secret` is the only one you must give. It needs at least 32 bytes, and Bond checks only the length, not that it is random: make it once with `SecureRandom.hex(32)` (64 hex digits from 32 random bytes), keep it in the environment or a file, and never put it in the source. The program stops at the call of `sessions` when an option is wrong (a short secret, an empty name, a `max_age` below 1, a `same_site` that is not `Strict`, `Lax` or `None`, or `None` without `secure`), as `Bond.static` does for a bad folder.

| Option | Default | |
|---|---|---|
| `secret` | | the key that signs the cookie |
| `old_secrets` | `[]` | keys that signed cookies before (see the rotation below) |
| `name` | `_bond_session` | the name of the cookie (in production `__Host-session`, see below) |
| `max_age` | `1_209_600` | seconds that a session lasts (two weeks) |
| `secure` | `false` | adds `Secure`: set it in production, over HTTPS |
| `same_site` | `"Lax"` | `"Strict"`, `"Lax"` or `"None"` |
| `path`, `domain` | `"/"`, `""` | those of the cookie |

The cookie is always `HttpOnly`. In production use `name: "__Host-session"` with `secure: true`, the default `path` and no `domain`: a browser accepts a `__Host-` cookie only from a secure page for the exact host, so a sibling subdomain cannot plant a cookie of that name (it could plant one that is signed, with its own session, since the first cookie of a name wins). `Secure` is off by default for the reason that `Bond.set_cookie` has no `Secure`: a `Secure` cookie is dropped over plain HTTP, which would break a program in development.

The end date is inside the signed data, so a client that keeps an old cookie does not get a longer session. Every change writes a cookie that lasts `max_age` from that moment; a session that is only read is not extended.

## What is signed, and what is not

The cookie is `payload.signature`, both in base64url. The signature covers the name of the cookie and the payload, with the secret. A cookie that is missing, malformed, changed, expired, or signed with a secret that Bond does not know is an empty session: it is never an error of the client, and no 4xx comes of it.

The payload is not encrypted: anyone who has the cookie can read what it holds. Keep an id or a name there, not a secret, and look up the rest on the server. The session is also a small one: a cookie over 3800 bytes would be dropped by browsers, so Bond makes the answer a 500 (through `on_error`) instead of sending it.

Log in with a new session: call `clear_session` before you set the user, so nothing of the session the visitor had before is kept. A signed cookie cannot be revoked on the server before it expires: a logout deletes it in the browser of the visitor, but a copy of it stays valid until its `max_age`. Use a short `max_age` for what must end soon.

## Rotating the secret

To change the secret without ending every session, put the new one in `secret` and the old one in `old_secrets`. Bond reads a cookie signed with any of them, and writes it again with `secret` on the first request that has it. That cookie gets a new `max_age` from that moment, so a session that is in use outlives the rotation and an old one that nobody uses ends as before. Remove the old secret after `max_age` seconds, when the last cookie that it signed has expired.

## Testing

`Testing.session_cookie(options, data)` gives the `name=value` of a cookie signed as `sessions` would sign it, so a test of a route for logged-in users needs no login first. It does not check the options as `sessions` does: a short secret, or a negative `max_age` (which gives an expired cookie), are accepted.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

OPTIONS = Bond.SessionOptions(secret: "a-secret-of-at-least-32-bytes-ok")

def login(conn: Bond.Conn) -> Result[Bond.Conn]
  signed_in = Bond.set_session(Bond.clear_session(conn), "user", "ana")
  return ok(Bond.text(signed_in, 200, "welcome"))
end

def me(conn: Bond.Conn) -> Result[Bond.Conn]
  user = Bond.get_session(conn, "user").unwrap_or("nobody")
  return ok(Bond.text(conn, 200, "hello #{user}"))
end

def logout(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(Bond.clear_session(conn), 200, "bye"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.sessions(OPTIONS)
    |> Bond.get("/login", &login)
    |> Bond.get("/me", &me)
    |> Bond.get("/logout", &logout)
  )
  puts(Testing.text(Testing.request(app, "GET", "/me")).unwrap!)

  # The cookie of the answer goes back in the next request, as a browser does.
  answer = Testing.request(app, "GET", "/login")
  cookie = HTTP.header_values(answer.headers, "set-cookie").first.split(";").first
  headers = [Header(name: "Cookie", value: cookie)]
  puts(Testing.text(Testing.request(app, "GET", "/me", headers)).unwrap!)

  # A visitor who is logged in, with no login in the test.
  made = Testing.session_cookie(OPTIONS, {"user": "bo"}).unwrap!
  puts(Testing.text(Testing.request(app, "GET", "/me", [Header(name: "Cookie", value: made)])).unwrap!)

  # A changed cookie is an empty session.
  changed = "_bond_session=A" + cookie.split("=")[1].slice(1, 40) + ".AAAA"
  puts(Testing.text(Testing.request(app, "GET", "/me", [Header(name: "Cookie", value: changed)])).unwrap!)

  gone = Testing.request(app, "GET", "/logout", headers)
  puts(HTTP.header_values(gone.headers, "set-cookie").first)
end
```

```output
hello nobody
hello ana
hello bo
hello nobody
_bond_session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT
```

`sessions` adds a `before` and an `after` filter (see [Filters](../filters/)), so the order of the calls matters as it does for any filter: call it before the filters that read the session. Without it, `set_session` changes the `Conn` and nothing is sent.
