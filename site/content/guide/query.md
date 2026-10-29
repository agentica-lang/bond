---
title: Query and forms
weight: 3
description: Read the query string and a form body, decoded with std/uri.
---

# Query and forms

`Bond.query(conn, "q")` is the first value of `q` in the query string, decoded with `std/uri`: `+` is a space and `%XX` is a byte. `conn.query` stays the raw text after `?`.

`Bond.query_int(conn, "page")` reads a whole number, and `Bond.query_all(conn, "tag")` gives every value of a name that repeats, in order (an empty list when the name is not there). A piece with no equal sign, as in `?debug`, has the value `""`, and so has `?q=`.

Each one is a `Result`, and a failure is an error that makes a 400, so `try` answers it. A name that is missing is `query parameter q is missing`, a number that is not one is `page must be an integer`, and a query string that does not decode is `the query string is not valid`.

## Read many fields at once

Each call decodes the whole query string again, so a handler that reads several fields calls `Bond.query_params(conn)` once. It gives a `Map[String, List[String]]`: each name with its values in the order they were sent, the names in the order of their first appearance. `Bond.form_params(conn)` does the same for a form body. A form of 1 MiB read field by field with `Bond.form` costs the decoding of 1 MiB each time.

## Invalid is not missing

A `%` that is not followed by two hex digits, or bytes that are not UTF-8, anywhere in the string, in a name or in a value you do not read, make all of it invalid. That is a 400, as in Rack. So `Bond.query(conn, "q").unwrap_or("")` also turns an invalid query string into the default, and does not tell it from a missing name. To tell them apart, call `query_params` first with `try`, and take the optional value from the map:

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def search(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.query_params(conn)
  page = fields.get("page", ["1"])[0]
  tags = fields.get("tag", [])
  q = fields.get("q", [""])[0]
  return ok(Bond.text(conn, 200, "q=#{q} page=#{page} tags=#{tags.join(",")}"))
end

def get(app: Bond.App, target: String) -> Void
  response = Testing.request(app, "GET", target)
  puts("#{response.status} #{response.body}")
end

def main() -> Void
  app = Bond.app() |> Bond.get("/search", &search)
  get(app, "/search?q=caf%C3%A9+au+lait&tag=b&tag=a&page=3")
  get(app, "/search?q=x")
  get(app, "/search?q=x&other=%zz")
end
```

```output
200 q=café au lait page=3 tags=b,a
200 q=x page=1 tags=
400 the query string is not valid
```

## Numbers

`query_int` and `form_int` accept negative numbers: check the range in the handler. A plain `+` before the digits is a space, so `?n=+5` is a 400, and `?n=%2B5` is 5. A number outside 64 bits is a 400 too.

## Forms

`Bond.form`, `Bond.form_int`, `Bond.form_all` and `Bond.form_params` read the body of a form: `application/x-www-form-urlencoded`. The request must have exactly one `Content-Type`, and it must be that type, in any case and with any parameters. Another type, or none, is a 400 with `content type must be application/x-www-form-urlencoded`. A field that is missing is `form field name is missing`, and a body that does not decode is `the form is not valid`.

The charset parameter is ignored: the body is read as UTF-8. A line break at the end of the body stays in the last value, as in Rack.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def signup(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.form(conn, "name")
  age = try Bond.form_int(conn, "age")
  return ok(Bond.text(conn, 201, "welcome #{name}, #{age}"))
end

def post_form(app: Bond.App, body: String) -> Void
  headers = [Header(name: "Content-Type", value: "application/x-www-form-urlencoded")]
  response = Testing.request(app, "POST", "/signup", headers, body)
  puts("#{response.status} #{response.body}")
end

def main() -> Void
  app = Bond.app() |> Bond.post("/signup", &signup)
  post_form(app, "name=Ana+Mar%C3%ADa&age=30")
  post_form(app, "name=Ana&age=old")
  post_form(app, "name=Ana")
end
```

```output
201 welcome Ana María, 30
400 age must be an integer
400 form field age is missing
```

## The path is not decoded

The path of a request is not decoded yet: a `:name` param keeps its `%XX` text. Decode it in the handler with `URI.decode_uri_component` (a `+` stays a plus there, as it should in a path):

```agentica
import URI from "std/uri"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def show(conn: Bond.Conn) -> Result[Bond.Conn]
  raw = try Bond.param(conn, "name")
  case URI.decode_uri_component(raw)
    ok(name) -> return ok(Bond.text(conn, 200, "file #{name}"))
    error(_) -> return Bond.bad_request("the name is not valid")
  end
end

def main() -> Void
  app = Bond.app() |> Bond.get("/files/:name", &show)
  puts(Testing.request(app, "GET", "/files/caf%C3%A9").body)
  puts(Testing.request(app, "GET", "/files/a+b").body)
  puts(Testing.request(app, "GET", "/files/%zz").status)
end
```

```output
file café
file a+b
400
```
