## The query string and the form body of a request, read with `std/uri`.

import URI from "std/uri"
import Conns from "conn"
import {Conn} from "conn"

FORM_TYPE = "application/x-www-form-urlencoded"

## Every name of the query string with its values, decoded (`+` is a space and `%XX` is a byte), in the order they
## were sent. It decodes the whole string once: a handler that reads many fields uses it, and one that reads one or
## two uses `query`. A `%` that is not followed by two hex digits, or bytes that are not UTF-8, anywhere in the
## string make all of it invalid: an error that makes a 400 (see `bad_request`).
export def query_params(conn: Conn) -> Result[Map[String, List[String]]]
  case URI.decode_www_form(conn.query)
    ok(pairs) -> return ok(group(pairs))
    error(_) -> return Conns.bad_request("the query string is not valid")
  end
end

## Like `query_params`, for the body of a form (`application/x-www-form-urlencoded`). The request must have exactly
## one `Content-Type`, and it must be that type; the body is read as UTF-8 whatever its charset says.
export def form_params(conn: Conn) -> Result[Map[String, List[String]]]
  if Conns.media_type(conn) != FORM_TYPE
    return Conns.bad_request("content type must be #{FORM_TYPE}")
  end

  case String.from_bytes(conn.body)
    ok(text) ->
      case URI.decode_www_form(text)
        ok(pairs) -> return ok(group(pairs))
        error(_) -> return Conns.bad_request("the form is not valid")
      end

    error(_) -> return Conns.bad_request(Conns.NOT_UTF8)
  end
end

## The first value of `name` in the query string. A name that is not there, and a query string that does not
## decode, are an error that makes a 400, so `try Bond.query(...)` answers them. It decodes the whole string each
## time: use `query_params` to read several. `conn.query` is the raw text.
export def query(conn: Conn, name: String) -> Result[String]
  fields = try query_params(conn)
  return one(fields, name, "query parameter")
end

## Like `query`, for a whole number (negative too: check the range in the handler). Text that is not one is a 400.
export def query_int(conn: Conn, name: String) -> Result[Int]
  fields = try query_params(conn)
  return whole(fields, name, "query parameter")
end

## Every value of `name` in the query string, in order: an empty list when the name is not there.
export def query_all(conn: Conn, name: String) -> Result[List[String]]
  fields = try query_params(conn)
  return ok(fields.get(name, []))
end

## The first value of `name` in the body of a form, like `query` (and with the rules of `form_params`).
export def form(conn: Conn, name: String) -> Result[String]
  fields = try form_params(conn)
  return one(fields, name, "form field")
end

## Like `form`, for a whole number. Text that is not one is a 400.
export def form_int(conn: Conn, name: String) -> Result[Int]
  fields = try form_params(conn)
  return whole(fields, name, "form field")
end

## Every value of `name` in the form, in order: an empty list when the field is not there.
export def form_all(conn: Conn, name: String) -> Result[List[String]]
  fields = try form_params(conn)
  return ok(fields.get(name, []))
end

# The values of each name in the order they were sent, the names in the order of their first appearance.
def group(pairs: List[URI.Pair]) -> Map[String, List[String]]
  fields: Map[String, List[String]] = {}
  for pair in pairs
    fields = fields.put(pair.name, fields.get(pair.name, []).push(pair.value))
  end

  return fields
end

# `what` names the kind of field in the message; `name` is the program's, never the client's text.
def one(fields: Map[String, List[String]], name: String, what: String) -> Result[String]
  case fields.get(name)
    some(found) -> return ok(found[0])
    none -> return Conns.bad_request("#{what} #{name} is missing")
  end
end

def whole(fields: Map[String, List[String]], name: String, what: String) -> Result[Int]
  text = try one(fields, name, what)
  case text.to_i
    ok(number) -> return ok(number)
    error(_) -> return Conns.bad_request("#{name} must be an integer")
  end
end
