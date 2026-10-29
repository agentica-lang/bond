## The connection: the request being served and the response being built. A `Conn` never changes; every helper
## gives a new one.

# An `error` whose message starts with this text is a 400, and the rest is the body. `bad_request` is the way to
# make one; the text is not part of the API. No error message may start with it unless it is meant for the client:
# `json_body` cuts the client's text out of the codec messages, and a decoded value is never put in an error.
export BAD_REQUEST = "bad request: "

export INTERNAL_ERROR = "Internal Server Error"

PARSE_PREFIX = "JSON.parse: "

REDIRECT_STATUSES = [301, 302, 303, 307, 308]

# The characters besides letters and digits that the server accepts in a header name (RFC 9110 token).
TOKEN_SYMBOLS = "!#$%&'*+-.^_`|~"

ASCII_LIMIT = 127
LATIN1_LIMIT = 255

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
## clears the body and the content type and halts, so a `before` filter can use it. Another `code` is a runtime
## error in the handler, so a 500. `location` must be ASCII (percent-encode anything else): the answer is a 500
## otherwise. Do not build it from text a client sent without checking it, or the redirect is open to any site.
export def redirect(conn: Conn, location: String, code: Int = 302) -> Conn
  if not REDIRECT_STATUSES.any? do |allowed| allowed == code end
    bad: Result[Conn] = error("bond: #{code} is not a redirect status (301, 302, 303, 307 or 308)")
    return bad.unwrap!
  end

  kept = conn.response_headers.select do |field| field.name.downcase != "content-type" end
  untyped = conn.with(response_headers: kept)
  return header(untyped, "location", location).with(status: code, response_body: "", halted: true)
end

## Answers `value` encoded as JSON. It sets `Content-Type`; call `header` after it to use another.
export def json(conn: Conn, status: Int, value: Json) -> Conn
  return header(conn, "content-type", "application/json").with(status: status, response_body: JSON.encode(value))
end

## Answers `body` as plain text and stops the filters and the handler that come after.
export def halt(conn: Conn, status: Int, body: String) -> Conn
  return text(conn, status, body).with(halted: true)
end

## Adds a response header after the ones of the same name, as `Set-Cookie` needs: each is a header of its own and
## they are never joined.
export def add_header(conn: Conn, name: String, value: String) -> Conn
  return conn.with(response_headers: conn.response_headers.push(Header(name: name, value: value)))
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

## Decodes the body of the request with `codec` (`JSON.codec(User)`). The request must have one `Content-Type`, and
## it must be `application/json` or a `type/name+json`, with any parameters (the body is read as UTF-8 whatever the
## charset says). A missing, repeated or other content type, an empty body, and a body that is not one JSON
## document that fits the struct, are an error that makes a 400 (see `bad_request`) with a short message, so
## `try Bond.json_body(...)` answers them. The message names the struct field up to the first `[` of the codec's
## path, so the key of a map and the index of a list that the client sent are not in it. The size of the body is
## limited by the server (`max_body_bytes`).
export def json_body[T](conn: Conn, codec: JSON.Codec[T]) -> Result[T]
  if not json_content_type?(conn)
    return bad_request("content type must be application/json")
  end

  if conn.body.empty?
    return bad_request("the body is empty")
  end

  case codec.decode(conn.body)
    ok(value) -> return ok(value)
    error(message) -> return bad_request("invalid body: #{decode_problem(message)}")
  end
end

## The media type of the request in lowercase, without its parameters (`; charset=utf-8`), or "" when the request
## has no `Content-Type` or more than one.
export def media_type(conn: Conn) -> String
  values = conn.headers.select do |field| field.name.downcase == "content-type" end
  if values.size != 1
    return ""
  end

  return values[0].value.split(";")[0].strip().downcase
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
## `Content-Length` or `Transfer-Encoding` header, a header name that is not a token, a value that is not Latin-1
## text without control characters, and a body with a 204 or 304, so this checks the same (and that `Location` is
## ASCII, since a Latin-1 byte there is not a URL): a 204 or
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

  for field in conn.response_headers
    if not token?(field.name)
      return "the header name #{field.name.inspect} is not a token"
    end

    if not field.value.split("").all? do |ch| value_char?(ch) end
      return "the value of the header #{field.name} has a control or non-Latin-1 character"
    end

    if field.name.downcase == "location" and not field.value.split("").all? do |ch| ch.code <= ASCII_LIMIT end
      return "the Location header must be ASCII: percent-encode it"
    end
  end

  return ""
end

def token?(name: String) -> Bool
  return not name.empty? and name.split("").all? do |ch| token_char?(ch) end
end

def token_char?(ch: String) -> Bool
  code = ch.code
  digit = code >= 48 and code <= 57
  upper = code >= 65 and code <= 90
  lower = code >= 97 and code <= 122
  return digit or upper or lower or TOKEN_SYMBOLS.index_of(ch).ok?
end

def value_char?(ch: String) -> Bool
  code = ch.code
  return code == 9 or (code >= 32 and code != 127 and code <= LATIN1_LIMIT)
end

# application/json or type/name+json, in any case, with or without parameters (`; charset=utf-8`).
def json_content_type?(conn: Conn) -> Bool
  media = media_type(conn)
  if media == "application/json"
    return true
  end

  parts = media.split("/")
  return parts.size == 2 and not parts[0].empty? and parts[1].length > 5 and parts[1].end_with?("+json")
end

# The error of the codec is `path: problem`, and the path may hold a map key or a list index that the client sent
# (`scores["KEY"]`, `tags[0]`): keep the text before the first `[` and the problem after the last `: `. A parse
# error has the prefix `JSON.parse: `, which is dropped.
def decode_problem(message: String) -> String
  if message.start_with?(PARSE_PREFIX)
    return message.slice(PARSE_PREFIX.length, message.length - PARSE_PREFIX.length)
  end

  case message.index_of("[")
    ok(at) -> return "#{message.slice(0, at)}: #{message.split(": ").last}"
    error(_) -> return message
  end
end
