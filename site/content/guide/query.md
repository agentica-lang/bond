---
title: Query and forms
weight: 3
description: Read the query string and a form body, decoded with std/uri.
---

# Query and forms

`Bond.query(conn, "q")` is the first value of `q` in the query string, decoded with `std/uri`: `+` is a space and `%XX` is a byte. `conn.query` stays the raw text after `?`.

`Bond.query_int(conn, "page")` reads a whole number, and `Bond.query_all(conn, "tag")` gives every value of a name that repeats, in order (an empty list when the name is not there). A piece with no equal sign, as in `?debug`, has the value `""`.

Each one is a `Result`, and a failure is an error that makes a 400, so `try` answers it. A name that is missing is `query parameter q is missing`, a number that is not one is `page must be an integer`, and a query string with a bad `%` or bytes that are not UTF-8 is `the query string is not valid`. For an optional value, use `unwrap_or`, as `page` does below.

## Forms

`Bond.form`, `Bond.form_int` and `Bond.form_all` do the same for the body of a form: `application/x-www-form-urlencoded`. The request must have exactly one `Content-Type`, and it must be that type, in any case and with any parameters. Another type, or none, is a 400 with `content type must be application/x-www-form-urlencoded`. A field that is missing is `form field name is missing`, and a body that does not decode is `the form is not valid`.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def search(conn: Bond.Conn) -> Result[Bond.Conn]
  q = try Bond.query(conn, "q")
  page = Bond.query_int(conn, "page").unwrap_or(1)
  tags = try Bond.query_all(conn, "tag")
  return ok(Bond.text(conn, 200, "q=#{q} page=#{page} tags=#{tags.join(",")}"))
end

def signup(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.form(conn, "name")
  age = try Bond.form_int(conn, "age")
  return ok(Bond.text(conn, 201, "welcome #{name}, #{age}"))
end

def get(app: Bond.App, target: String) -> Void
  response = Testing.request(app, "GET", target, [], "")
  puts("#{response.status} #{response.body}")
end

def post_form(app: Bond.App, body: String) -> Void
  headers = [Header(name: "Content-Type", value: "application/x-www-form-urlencoded")]
  response = Testing.request(app, "POST", "/signup", headers, body)
  puts("#{response.status} #{response.body}")
end

def main() -> Void
  app = Bond.app() |> Bond.get("/search", &search) |> Bond.post("/signup", &signup)
  get(app, "/search?q=caf%C3%A9+au+lait&tag=b&tag=a&page=3")
  get(app, "/search?q=x")
  get(app, "/search?page=2")
  get(app, "/search?q=%zz")
  post_form(app, "name=Ana+Mar%C3%ADa&age=30")
  post_form(app, "name=Ana&age=old")
  post_form(app, "name=Ana")
end
```

```output
200 q=café au lait page=3 tags=b,a
200 q=x page=1 tags=
400 query parameter q is missing
400 the query string is not valid
201 welcome Ana María, 30
400 age must be an integer
400 form field age is missing
```

The path of a request is not decoded yet: a `:name` param keeps its `%XX` text.
