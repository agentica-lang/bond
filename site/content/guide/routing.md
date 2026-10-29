---
title: Routing
weight: 1
description: Routes, path params and what happens when nothing matches.
---

# Routing

`Bond.get`, `Bond.post`, `Bond.put`, `Bond.patch` and `Bond.delete` take the app, a pattern and a handler, and return the app. The app is a `Bond.App`, and a handler is a `Bond.Handler`, which is a `Fn[Bond.Conn, Result[Bond.Conn]]`: write `&name` for a function that has only the `Conn`, and a block for one that needs more.

## Params

A segment that starts with a colon, as in `/users/:id/posts/:post_id`, matches one segment. Read it with `Bond.param(conn, "id")`, which is a `Result[String]`, or `Bond.param_int(conn, "id")`. Text that is not a number is a 400.

Neither the params nor the literal segments are decoded: `%20` stays `%20`, and a `/café` route never matches `/caf%C3%A9`, yet. The query string is decoded: see [Query and forms](/guide/query/).

## How routes match

The routes are kept as a tree of path segments, and a request walks the tree once, so a lookup typically depends on the length of the path and not on the number of routes. A path can make the walk go back from a literal branch to a param branch, so in the worst case it visits more branches, never more than the tree has. A trailing or a double slash does not matter: `/posts/` and `//posts` are `/posts`.

- A literal segment wins over a `:param` at the same place, whatever the order the routes were added in: `/posts/latest` is not taken by `/posts/:id`, even when `/posts/:id` was added first.
- When the literal branch has no route to the end of the path, the walk goes back to the param: with `/docs/guide/intro` and `/docs/:page/edit`, the path `/docs/guide/edit` is `/docs/:page/edit` with `page` set to `guide`.
- The path is chosen first, then the method. If the route that the path reaches has no handler for the method, the answer is a 405 and `Allow` lists the methods of that route only. The methods of `/posts/:id` are not borrowed for `/posts/latest`. This differs from Sinatra, which tries the next route: with `GET /users/me` and `PUT /users/:id`, a `PUT /users/me` is a 405 here, and it would reach `:id` there.
- The routes of one path share one param name, whatever their methods: `GET /users/:id` and `POST /users/:uid` stop the program. Use `:id` for both.

Two mistakes stop the program when the route is added, like a bad pattern: the same method and pattern twice (`/posts` and `/posts/` are the same pattern), and two names for the param at the same place, such as `/users/:id` with `/users/:name/posts` or with `POST /users/:uid`. Use one name at each place.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def show_post(conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  return ok(Bond.text(conn, 200, "post #{id}"))
end

def latest(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "the latest post"))
end

def intro(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "the intro"))
end

def edit(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "edit #{try Bond.param(conn, "page")}"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/posts/:id", &show_post)
    |> Bond.get("/posts/latest", &latest)
    |> Bond.get("/docs/guide/intro", &intro)
    |> Bond.get("/docs/:page/edit", &edit)
  )
  puts(Testing.request(app, "GET", "/posts/42", [], "").body)
  puts(Testing.request(app, "GET", "/posts/latest/", [], "").body)
  puts(Testing.request(app, "GET", "/docs/guide/edit", [], "").body)
  response = Testing.request(app, "POST", "/posts/latest", [], "")
  puts("#{response.status} #{HTTP.header_values(response.headers, "allow")}")
end
```

```output
post 42
the latest post
edit guide
405 ["GET, HEAD"]
```

## No route

A path with no route is a 404 with the body `not found`; [Errors](/guide/errors/) shows how to answer it with your own page. A path with a route for other methods only is a 405 with an `Allow` header that lists the methods.

`HEAD` uses the route of `GET` (the server drops the body), and `Allow` lists `HEAD` where it lists `GET`. `OPTIONS` is not answered by Bond: it is a 405 unless you add the route.

A pattern must start with `/` and name each param once, or the program stops when the route is added.
