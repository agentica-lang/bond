## The connection: the request being served and the response being built. A `Conn` never changes; every helper
## gives a new one.

## An `error` that starts with this text is a 400, and the text after it is the body (`param_int` uses it).
export BAD_REQUEST = "bad request: "

export type Handler = Fn[Conn, Result[Conn]]

## `query` is the raw text after `?`. `params` are the `:name` segments of the route that matched. Request header
## names are in lowercase. A new `Conn` answers 200 with no body.
export struct Conn
  method: String
  path: String
  query: String
  params: Map[String, String]
  headers: List[Header]
  body: String
  status: Int
  response_headers: List[Header]
  response_body: String
  halted: Bool
end

## The `Conn` of a request, before any route or filter.
export def from_request(request: HttpRequest) -> Conn
  query = ""
  case request.target.index_of("?")
    ok(at) -> query = request.target.slice(at + 1, request.target.length - at - 1)
    error(_) -> query = ""
  end

  return Conn(
    method: request.method,
    path: request.path,
    query: query,
    params: {},
    headers: request.headers,
    body: request.body,
    status: 200,
    response_headers: [],
    response_body: "",
    halted: false,
  )
end

## Answers `body` as plain text.
export def text(conn: Conn, status: Int, body: String) -> Conn
  return header(conn, "content-type", "text/plain; charset=utf-8").with(status: status, response_body: body)
end

## Answers `value` encoded as JSON.
export def json(conn: Conn, status: Int, value: Json) -> Conn
  return header(conn, "content-type", "application/json").with(status: status, response_body: JSON.encode(value))
end

## Answers `body` as plain text and stops the filters and the handler that come after.
export def halt(conn: Conn, status: Int, body: String) -> Conn
  return text(conn, status, body).with(halted: true)
end

## Sets a response header, replacing the one of the same name (the case does not matter).
export def header(conn: Conn, name: String, value: String) -> Conn
  kept = conn.response_headers.select do |other| other.name.downcase != name.downcase end
  return conn.with(response_headers: kept.push(Header(name: name, value: value)))
end

## The first value of a request header (the case of the name does not matter), or an error when there is none.
export def request_header(conn: Conn, name: String) -> Result[String]
  values = conn.headers.select do |other| other.name.downcase == name.downcase end
  if values.empty?
    return error("no header #{name}")
  end

  return ok(values[0].value)
end

## The text of the `:name` segment of the route, or an error when the route has no such segment.
export def param(conn: Conn, name: String) -> Result[String]
  return conn.params.get(name)
end

## Like `param`, for a whole number. Text that is not one is a 400 (`BAD_REQUEST`).
export def param_int(conn: Conn, name: String) -> Result[Int]
  text = try param(conn, name)
  case text.to_i
    ok(number) -> return ok(number)
    error(_) -> return error("#{BAD_REQUEST}#{name} must be an integer")
  end
end

## The response of the `Conn`, as `std/http` sends it.
export def to_response(conn: Conn) -> HttpResponse
  return HttpResponse(status: conn.status, headers: conn.response_headers, body: conn.response_body)
end
