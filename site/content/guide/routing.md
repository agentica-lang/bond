---
title: Routing
weight: 1
description: Routes, path params and what happens when nothing matches.
---

# Routing

`Bond.get`, `Bond.post`, `Bond.put`, `Bond.patch` and `Bond.delete` take the app, a pattern and a handler, and return the app. A handler is a `Fn[Bond.Conn, Result[Bond.Conn]]`: write `&name` for a function that has only the `Conn`, and a block for one that needs more.

## Params

A segment that starts with a colon, as in `/users/:id/posts/:post_id`, matches one segment. Read it with `Bond.param(conn, "id")`, which is a `Result[String]`, or `Bond.param_int(conn, "id")`. Text that is not a number is a 400.

Neither the params nor the literal segments are decoded: `%20` stays `%20`, and a `/café` route never matches `/caf%C3%A9`, until `std/uri` is in Agentica.

## Order

Routes are tried in the order they were added, so put `/posts/latest` before `/posts/:id`. A trailing slash does not matter: `/posts/` is `/posts`.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def show_post(conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  return ok(Bond.text(conn, 200, "post #{id}"))
end

def latest(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "the latest post"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/posts/latest", &latest)
    |> Bond.get("/posts/:id", &show_post)
  )
  puts(Testing.request(app, "GET", "/posts/42", [], "").body)
  puts(Testing.request(app, "GET", "/posts/latest/", [], "").body)
  puts(Testing.request(app, "GET", "/posts/new", [], "").status)
end
```

```output
post 42
the latest post
400
```

## No route

A path with no route is a 404 with the body `not found`; [Errors](/guide/errors/) shows how to answer it with your own page. A path with a route for other methods only is a 405 with an `Allow` header that lists the methods.

`HEAD` uses the route of `GET` (the server drops the body), and `Allow` lists `HEAD` where it lists `GET`. `OPTIONS` is not answered by Bond: it is a 405 unless you add the route.

A pattern must start with `/` and name each param once, or the program stops when the route is added.
