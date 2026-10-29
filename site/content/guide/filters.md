---
title: Filters
weight: 8
description: Code that runs before and after every route.
---

# Filters

`Bond.before(app, filter)` runs a filter before the route and `Bond.after(app, filter)` after it. A filter is a handler too, a `Fn[Bond.Conn, Result[Bond.Conn]]`. Filters run in the order they were added.

A `before` filter that halts, or gives an error, skips the filters and the handler after it. The `after` filters still run, for a halted answer and for a 404 too. They do not run when a handler crashes.

`Bond.log_request` is a `before` filter that writes `METHOD /path` to stderr.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def require_token(conn: Bond.Conn) -> Result[Bond.Conn]
  if Bond.request_header(conn, "x-token").unwrap_or("") != "letmein"
    return ok(Bond.halt(conn, 401, "unauthorized"))
  end

  return ok(conn)
end

def sign(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.header(conn, "x-powered-by", "bond"))
end

def secret(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "the secret"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.before(&require_token)
    |> Bond.after(&sign)
    |> Bond.get("/secret", &secret)
  )
  denied = Testing.request(app, "GET", "/secret")
  puts("#{denied.status} #{denied.body}")
  allowed = Testing.request(app, "GET", "/secret", [Header(name: "X-Token", value: "letmein")])
  puts("#{allowed.status} #{allowed.body}")
  puts(HTTP.header_values(denied.headers, "x-powered-by")[0])
end
```

```output
401 unauthorized
200 the secret
bond
```

The 401 came from the filter, and the `after` filter still signed it.
