## The query string and the form body of a request, read with `std/uri`.

import URI from "std/uri"
import Conns from "conn"
import {Conn} from "conn"

FORM_TYPE = "application/x-www-form-urlencoded"

## The first value of `name` in the query string, decoded (`+` is a space and `%XX` is a byte). A name that is not
## there, and a query string that does not decode, are an error that makes a 400 (see `bad_request`), so
## `try Bond.query(...)` answers them; use `unwrap_or` for an optional one. `conn.query` is the raw text.
export def query(conn: Conn, name: String) -> Result[String]
  pairs = try query_pairs(conn)
  return one(pairs, name, "query parameter")
end

## Like `query`, for a whole number. Text that is not one is a 400.
export def query_int(conn: Conn, name: String) -> Result[Int]
  pairs = try query_pairs(conn)
  return whole(pairs, name, "query parameter")
end

## Every value of `name` in the query string, in order: an empty list when the name is not there.
export def query_all(conn: Conn, name: String) -> Result[List[String]]
  pairs = try query_pairs(conn)
  return ok(values(pairs, name))
end

## The first value of `name` in the body of a form (`application/x-www-form-urlencoded`), decoded like `query`. The
## request must have exactly one `Content-Type`, and it must be that type; otherwise, and for a field that is not
## there or a body that does not decode, it is an error that makes a 400.
export def query_params(conn: Conn) -> Result[Map[String, List[String]]]
  return error("not written yet")
end

export def form_params(conn: Conn) -> Result[Map[String, List[String]]]
  return error("not written yet")
end

export def form(conn: Conn, name: String) -> Result[String]
  pairs = try form_pairs(conn)
  return one(pairs, name, "form field")
end

## Like `form`, for a whole number. Text that is not one is a 400.
export def form_int(conn: Conn, name: String) -> Result[Int]
  pairs = try form_pairs(conn)
  return whole(pairs, name, "form field")
end

## Every value of `name` in the form, in order: an empty list when the field is not there.
export def form_all(conn: Conn, name: String) -> Result[List[String]]
  pairs = try form_pairs(conn)
  return ok(values(pairs, name))
end

def query_pairs(conn: Conn) -> Result[List[URI.Pair]]
  case URI.decode_www_form(conn.query)
    ok(pairs) -> return ok(pairs)
    error(_) -> return Conns.bad_request("the query string is not valid")
  end
end

def form_pairs(conn: Conn) -> Result[List[URI.Pair]]
  if Conns.media_type(conn) != FORM_TYPE
    return Conns.bad_request("content type must be #{FORM_TYPE}")
  end

  case URI.decode_www_form(conn.body)
    ok(pairs) -> return ok(pairs)
    error(_) -> return Conns.bad_request("the form is not valid")
  end
end

def values(pairs: List[URI.Pair], name: String) -> List[String]
  matching = pairs.select do |pair| pair.name == name end
  return matching.map do |pair| pair.value end
end

# `what` names the kind of field in the message; `name` is the program's, never the client's text.
def one(pairs: List[URI.Pair], name: String, what: String) -> Result[String]
  found = values(pairs, name)
  if found.empty?
    return Conns.bad_request("#{what} #{name} is missing")
  end

  return ok(found[0])
end

def whole(pairs: List[URI.Pair], name: String, what: String) -> Result[Int]
  text = try one(pairs, name, what)
  case text.to_i
    ok(number) -> return ok(number)
    error(_) -> return Conns.bad_request("#{name} must be an integer")
  end
end
