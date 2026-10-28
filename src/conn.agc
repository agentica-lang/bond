## The connection: the request being served and the response being built. A `Conn` never changes; every helper
## gives a new one.

# An `error` whose message starts with this text is a 400, and the rest is the body. `bad_request` is the way to
# make one; the text is not part of the API. Once Bond decodes request data, take care that no error message that
# echoes a client's text can start with it.
export BAD_REQUEST = "bad request: "

export INTERNAL_ERROR = "Internal Server Error"

REDIRECT_STATUSES = [301, 302, 303, 307, 308]

export type Handler = Fn[Conn, Result[Conn]]

export type ErrorHandler = Fn[Conn, String, Result[Conn]]

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

## Answers `body` as plain text. It sets `Content-Type`; call `header` after it to use another.
export def text(conn: Conn, status: Int, body: String) -> Conn
  return header(conn, "content-type", "text/plain; charset=utf-8").with(status: status, response_body: body)
end

## Answers `body` as HTML. It sets `Content-Type`; call `header` after it to use another. The text is sent as it is,
## with no escaping: escape what comes from a client before you put it in `body`.
export def html(conn: Conn, status: Int, body: String) -> Conn
  return header(conn, "content-type", "text/html; charset=utf-8").with(status: status, response_body: body)
end

## Sets the status of the answer and nothing else.
export def status(conn: Conn, code: Int) -> Conn
  return conn.with(status: code)
end

## Answers with a redirect to `location`: a 302, or `code` when it is 301, 303, 307 or 308. It sets `Location`,
## clears the body and halts, so a `before` filter can use it. Another `code` stops the program with an error.
export def redirect(conn: Conn, location: String, code: Int = 302) -> Conn
  if not REDIRECT_STATUSES.any? do |allowed| allowed == code end
    bad: Result[Conn] = error("bond: #{code} is not a redirect status (301, 302, 303, 307 or 308)")
    return bad.unwrap!
  end

  return header(conn, "location", location).with(status: code, response_body: "", halted: true)
end

## Answers `value` encoded as JSON. It sets `Content-Type`; call `header` after it to use another.
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

## Gives an error that makes a 400 with `message` as its body, when a handler or filter returns it (or passes it on
## with `try`).
export def bad_request[T](message: String) -> Result[T]
  return error("#{BAD_REQUEST}#{message}")
end

## Like `param`, for a whole number. Text that is not one is a 400 (see `bad_request`).
export def param_int(conn: Conn, name: String) -> Result[Int]
  text = try param(conn, name)
  case text.to_i
    ok(number) -> return ok(number)
    error(_) -> return bad_request("#{name} must be an integer")
  end
end

## The response of the `Conn`, as `std/http` sends it. The server refuses a status outside 200 to 599, a
## `Content-Length` or `Transfer-Encoding` header and a body with a 204 or 304, so this checks the same: a 204 or
## 304 loses its body, and the other cases are a 500 with a warning on stderr. Both `Bond.run` and
## `Testing.request` come through here, so a test sees what a client would.
export def to_response(conn: Conn) -> HttpResponse
  problem = refusal(conn)
  if not problem.empty?
    IO.warn("bond: #{conn.method} #{conn.path}: invalid response: #{problem}")
    return HttpResponse(
      status: 500,
      headers: [Header(name: "content-type", value: "text/plain; charset=utf-8")],
      body: INTERNAL_ERROR,
    )
  end

  if conn.status == 204 or conn.status == 304
    return HttpResponse(status: conn.status, headers: conn.response_headers, body: "")
  end

  return HttpResponse(status: conn.status, headers: conn.response_headers, body: conn.response_body)
end

# Why the server would refuse the response, or "" when it would not.
def refusal(conn: Conn) -> String
  if conn.status < 200 or conn.status > 599
    return "the status #{conn.status} is outside 200 to 599"
  end

  names = conn.response_headers.map do |header| header.name.downcase end
  if names.any? do |name| name == "content-length" or name == "transfer-encoding" end
    return "Content-Length and Transfer-Encoding are set by the server"
  end

  return ""
end
