## Values that a filter keeps for the handler, so that the handler does not look them up again: the person a sign-in
## filter loaded, the account of a token. `assign` stores a value in the `Conn` under a name, and `assigned` reads it
## back as the type the reader asks for. The values live as long as the request: they are never sent to the client.
##
## A value is kept as the `Json` of `JSON.from(value)`, so the `Conn` does not need a type parameter, and a reader
## gets its type back with a codec (`JSON.codec(Person)`). What `JSON.encode` accepts can be assigned (structs, lists,
## maps with `String` keys, `Optional`, numbers, text); a value that it does not accept (a `Fn`, `Bytes`, a `Task`) is
## a `CHECK-NOT-ENCODABLE` error where `assign` is called.

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
## person = try Bond.assigned(conn, "person", JSON.codec(Person))
## ```
export def assigned[T](conn: Conn, key: String, codec: JSON.Codec[T]) -> Result[T]
  case conn.assigns.get(key)
    some(json) ->
      case codec.decode(json)
        ok(value) -> return ok(value)
        error(message) -> return error("assigned #{key}: #{message}")
      end

    none -> return error("nothing assigned under #{key}")
  end
end

## Whether a value was assigned under `key`.
export def assigned?(conn: Conn, key: String) -> Bool
  return conn.assigns.key?(key)
end
