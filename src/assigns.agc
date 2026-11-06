## Values that a filter keeps for the handler, so that the handler does not look them up again: the person a sign-in
## filter loaded, the account of a token. `assign` stores a value in the `Conn` under a name, and `assigned` reads it
## back as the type the reader asks for. The values live as long as the request: they are never sent to the client.
##
## A value is kept as the `Json` of `JSON.from(value)`, so the `Conn` does not need a type parameter, and a reader
## gets its type back with a codec (`Person.codec`). A codec is made from a struct, so assign a struct (its
## fields may be lists, maps with `String` keys, `Optional`s, numbers and text); wrap a bare number or list in one. The
## reader decodes the `Json` as `JSON.decode` does. A value whose type `JSON.encode` refuses (a `Fn`, `Bytes`, a
## `Task`, a user enum, or a struct holding one) is a `CHECK-NOT-ENCODABLE` error at the `assign` call.

import {Conn} from "conn"

## A `Conn` that has `value` under `key`; an earlier value of `key` is replaced. A `before` filter calls it, and the
## handler and the filters after it read the value with `assigned`.
export def assign[T](conn: Conn, key: String, value: T) -> Conn
  return conn.with(assigns: conn.assigns.put(key, JSON.from(value)))
end

## The value under `key` as the type of `codec`, as a `Result`. It is an `error` when nothing was assigned under `key`
## and when the value is not of that type. Both are mistakes of the program, not of the client, so a handler that
## uses `try` answers a 500; use `assigned?` to ask first.
##
## ```ruby
## person = try Bond.assigned(conn, "person", Person.codec)
## ```
export def assigned[T](conn: Conn, key: String, codec: Codec[T]) -> Result[T]
  json = try conn.assigns.get(key).to_result("nothing assigned under #{key}")
  case codec.decode(json)
    ok(value) -> return ok(value)
    error(message) -> return error("assigned #{key}: #{message}")
  end
end

## Whether a value was assigned under `key`.
export def assigned?(conn: Conn, key: String) -> Bool
  return conn.assigns.key?(key)
end
