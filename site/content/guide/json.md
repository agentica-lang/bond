---
title: JSON bodies
weight: 3
description: Decode the JSON body of a request into a struct.
---

# JSON bodies

`Bond.json_body(conn, JSON.codec(User))` decodes the body of the request into a struct, as a `Result[User]`. Declare the struct, pass its codec (`JSON.codec` is in Agentica 0.15.0), and use `try`: a body that does not fit is an error that makes a 400, so the handler needs no more code.

The request must say it is JSON: a `Content-Type` of `application/json`, or of a type that ends in `+json` such as `application/vnd.api+json`, with any parameters (`; charset=utf-8`) and in any case. A missing or other content type is a 400 with the body `content type must be application/json`, and an empty body is a 400 with `the body is empty`.

A body that is not one JSON document that fits the struct is a 400 with `invalid body: ` and what is wrong, such as `age: expected required field`. Extra keys are ignored. The message names the field of the struct and never repeats the text the client sent. The size of the body is limited by the server: a body over `max_body_bytes` is a 413 and never reaches the app (see [Running and options](/guide/server/)).

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

struct NewUser
  name: String
  age: Int
end

def create_user(conn: Bond.Conn) -> Result[Bond.Conn]
  user = try Bond.json_body(conn, JSON.codec(NewUser))
  return ok(Bond.text(conn, 201, "hello #{user.name}, #{user.age}"))
end

def post(app: Bond.App, type: String, body: String) -> Void
  headers = [Header(name: "Content-Type", value: type)]
  response = Testing.request(app, "POST", "/users", headers, body)
  puts("#{response.status} #{response.body}")
end

def main() -> Void
  app = Bond.app() |> Bond.post("/users", &create_user)
  post(app, "application/json", "{\"name\": \"Ana\", \"age\": 30}")
  post(app, "text/plain", "{\"name\": \"Ana\", \"age\": 30}")
  post(app, "application/json", "")
  post(app, "application/json", "{\"name\": \"Ana\"")
  post(app, "application/json", "{\"name\": \"Ana\"}")
  post(app, "application/json", "{\"name\": \"Ana\", \"age\": \"thirty\"}")
end
```

```output
201 hello Ana, 30
400 content type must be application/json
400 the body is empty
400 invalid body: invalid JSON
400 invalid body: age: expected required field
400 invalid body: age: expected signed 64-bit Int
```

To answer with JSON, keep using `Bond.json(conn, status, value)`: `JSON.from(user)` turns a struct into the `Json` value, so a response needs no codec.
