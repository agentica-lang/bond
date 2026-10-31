## The connection: the request being served and the response being built. A `Conn` never changes; every helper
## gives a new one.

import HTTP from "std/http"

# An `error` whose message starts with this text is a 400, and the rest is the body. `bad_request` is the way to
# make one; the text is not part of the API. No error message may start with it unless it is meant for the client:
# `json_body` cuts the client's text out of the codec messages, and a decoded value is never put in an error.
export BAD_REQUEST = "bad request: "

export INTERNAL_ERROR = "Internal Server Error"

PARSE_PREFIX = "JSON.parse: "

# The 400 of a body that is not UTF-8 text, the same for `body_text`, `json_body` and the form readers.
export NOT_UTF8 = "the body is not UTF-8 text"

NO_BODY = "".bytes

REDIRECT_STATUSES = [301, 302, 303, 307, 308]

# The characters besides letters and digits that the server accepts in a header name (RFC 9110 token).
TOKEN_SYMBOLS = "!#$%&'*+-.^_`|~"

ASCII_LIMIT = 127
LATIN1_LIMIT = 255

export type Handler = Fn[Conn, Result[Conn]]

export type ErrorHandler = Fn[Conn, String, Result[Conn]]

## `query` is the raw text after `?`. `params` are the `:name` segments of the route that matched. Request header
## names are in lowercase. `body` is the request body as the client sent it, `Bytes` of any content (`body_text` reads
## it as text). `response_body` is the body of the answer, also `Bytes`. `response_stream` is the channel of a streamed
## body (`stream`, `sse`); when it is set, the answer is that body and `response_body` is empty. `response_length` is
## the size of a streamed body when it is known (`stream` with a `length`, `send_file`). A new `Conn` answers 200 with
## no body.
export struct Conn
  method: String
  path: String
  query: String
  params: Map[String, String]
  headers: List[Header]
  body: Bytes
  status: Int
  response_headers: List[Header]
  response_body: Bytes
  response_stream: Optional[Channel[Bytes]]
  response_length: Optional[Int]
  halted: Bool
end

## The `Conn` of a request, before any route or filter.
export def from_request(request: HttpRequest) -> Conn
  query = ""
  case request.target.index_of("?")
    some(at) -> query = request.target.slice(at + 1, request.target.length - at - 1)
    none -> query = ""
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
    response_body: NO_BODY,
    response_stream: none,
    response_length: none,
    halted: false,
  )
end

## Answers `body` as plain text. It sets `Content-Type`; call `header` after it to use another.
export def text(conn: Conn, status: Int, body: String) -> Conn
  typed = header(release(conn), "content-type", "text/plain; charset=utf-8")
  return typed.with(status: status, response_body: body.bytes)
end

## Answers `body` as HTML. It sets `Content-Type`; call `header` after it to use another. The text is sent as it is,
## with no escaping: escape what comes from a client before you put it in `body`.
export def html(conn: Conn, status: Int, body: String) -> Conn
  typed = header(release(conn), "content-type", "text/html; charset=utf-8")
  return typed.with(status: status, response_body: body.bytes)
end

## Answers `body` as it is, `Bytes` of any content (an image, a file). It sets `Content-Type` to
## `application/octet-stream`; call `header` after it to use the real type.
export def bytes(conn: Conn, status: Int, body: Bytes) -> Conn
  typed = header(release(conn), "content-type", "application/octet-stream")
  return typed.with(status: status, response_body: body)
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
  untyped = release(conn).with(response_headers: kept)
  return header(untyped, "location", location).with(status: code, response_body: NO_BODY, halted: true)
end

## Answers `value` (a `Json`, such as `JSON.from(scores)` for a list or a map) as JSON. It sets `Content-Type`; call
## `header` after it to use another. For a struct, `json_as` encodes it once, with no `Json` in between.
export def json(conn: Conn, status: Int, value: Json) -> Conn
  return header(release(conn), "content-type", "application/json").with(
    status: status,
    response_body: JSON.encode(value).bytes,
  )
end

## Answers a struct encoded as JSON with its `codec` (`JSON.codec(Todo)`), like `json` but with no `Json` value in
## between: the struct is written once. A generic function cannot call `JSON.encode` on its type parameter, so the
## codec comes from the caller, as in `json_body`. A non-finite `Float` stops the handler with a runtime error
## (a 500), as `JSON.encode` does.
export def json_as[T](conn: Conn, status: Int, codec: JSON.Codec[T], value: T) -> Conn
  return header(release(conn), "content-type", "application/json").with(
    status: status,
    response_body: codec.encode(value).bytes,
  )
end

## Answers with the pieces that a task sends on `body`, as they come: the head goes out at once and each piece is one
## chunk, until the producer closes the channel. The producer is a task that the handler starts (`Task.spawn`), and it
## must close the channel on every path, or the response never ends. Its `send` is `error("channel: closed")` once the
## client has left, which is the signal to stop. Set the type with `header` (`sse` does it for an event stream). The
## `Content-Length` is the server's, so the headers cannot set it. A stream replaces the body set before it, and a
## body helper after it (`text`, `html`, `json`, `json_as`, `redirect`, `halt`) replaces the stream and closes its
## channel, so its producer stops. `stream` itself does not close the stream it replaces, so a filter can wrap the
## stream of the conn (read `conn.response_stream`, pump it into a new channel and call `stream` with that one): closing
## the old channel is then up to the caller. A 204 or a 304 has no body, so its channel is closed. `Testing.request`
## collects the pieces into the body.
##
## With a `length` (the size of the whole body, which a big file has before it is read) the server sends
## `Content-Length` and the pieces as they are, with no chunks. The producer must send exactly `length` bytes: a body
## that ends short, or goes over, closes the connection, so the client sees an incomplete body. `Testing.request` shows
## the `Content-Length` header of such a stream, since it has no socket.
export def stream(conn: Conn, status: Int, body: Channel[Bytes], length: Optional[Int] = none) -> Conn
  return conn.with(status: status, response_body: NO_BODY, response_stream: some(body), response_length: length)
end

## Answers a 200 stream of server-sent events (`text/event-stream`, no caching) from `events`: the producer sends the
## `Bytes` of `sse_event` and closes the channel. See `stream`.
export def sse(conn: Conn, events: Channel[Bytes]) -> Conn
  typed = header(header(conn, "content-type", "text/event-stream; charset=utf-8"), "cache-control", "no-cache")
  return stream(typed, 200, events)
end

## One server-sent event, ready to send on the channel of `sse`: an optional `event:` line, a `data:` line for each
## line of `data` and the empty line that ends the event. A line break of `data` (`\n`, `\r` or `\r\n`) starts a new
## `data:` line. A line break in `event` is replaced by a space, since it would start a field the caller did not write.
export def sse_event(data: String, event: String = "") -> Bytes
  lines = data.replace("\r\n", "\n").replace("\r", "\n").split("\n").map do |line| "data: #{line}\n" end
  name = ""
  if not event.empty?
    name = "event: #{event.replace("\r", " ").replace("\n", " ")}\n"
  end

  return "#{name}#{lines.join("")}\n".bytes
end

## Closes the stream of the conn, if it has one: for a stream that is not going to be sent, so its producer's next
## `send` fails and it stops.
export def close_stream(conn: Conn) -> Void
  case conn.response_stream
    some(body) -> body.close
    none -> return
  end
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

## Sets a response header, replacing the one of the same name (the case does not matter). `Set-Cookie` is the
## exception: it adds a header, so it never wipes the cookies set before it (see `set_cookie`).
export def header(conn: Conn, name: String, value: String) -> Conn
  if name.downcase == "set-cookie"
    return add_header(conn, name, value)
  end

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
  return conn.params.get(name).to_result("no param #{name}")
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

  case String.from_bytes(conn.body)
    ok(text) ->
      case codec.decode(text)
        ok(value) -> return ok(value)
        error(message) -> return bad_request("invalid body: #{decode_problem(message)}")
      end

    error(_) -> return bad_request(NOT_UTF8)
  end
end

## The body of the request as text, decoded as `HTTP.text` does: UTF-8 only (`us-ascii` is read as UTF-8), and a
## `charset` in `Content-Type` other than `utf-8` or `us-ascii` is refused. A body that does not decode is an error
## that makes a 400 (see `bad_request`), with a fixed message, so `try Bond.body_text(conn)` answers it. Read
## `conn.body` for the bytes as they came. The size of the body is limited by the server (`max_body_bytes`).
export def body_text(conn: Conn) -> Result[String]
  case HTTP.text(conn.body, conn.headers)
    ok(text) -> return ok(text)
    error(_) -> return bad_request(NOT_UTF8)
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
## 304 loses its body, and the other cases are a 500 with a warning on stderr. `Testing.request` comes through here,
## and `Bond.run` through `to_stream_response`, which has the same rules, so a test sees what a client would.
##
## A streamed body is read here to its end, as one `Bytes`, for a test. It is read until the producer closes the
## channel, `max_pieces` pieces (0 is no limit) or `timeout_ms` for the whole body (one gap between pieces may take all
## of it), and then the channel is closed so the producer stops; a body cut by the time limit says so on stderr. A
## `HEAD` gets no body and its channel is closed, as over a socket.
##
## The 10_000 default of `timeout_ms` is a literal (a default must be one): keep it in sync with `Apps.handle`,
## `Testing.request` and `specs/steps.agc`.
export def to_response(conn: Conn, max_pieces: Int = 0, timeout_ms: Int = 10_000) -> HttpResponse
  problem = refusal(conn)
  if not problem.empty?
    return refused(conn, problem)
  end

  if conn.status == 204 or conn.status == 304
    close_stream(conn)
    return HttpResponse(status: conn.status, headers: conn.response_headers, body: NO_BODY)
  end

  if conn.method == "HEAD" and conn.response_stream.some?
    close_stream(conn)
    return HttpResponse(status: conn.status, headers: sized_headers(conn), body: NO_BODY)
  end

  case conn.response_stream
    some(body) ->
      pieces = collect(conn, body, max_pieces, timeout_ms)
      return HttpResponse(status: conn.status, headers: sized_headers(conn), body: pieces)

    none -> return HttpResponse(status: conn.status, headers: conn.response_headers, body: conn.response_body)
  end
end

## The response of the `Conn` for `HTTP.listen_stream`: the rules of `to_response`, with the channel of a stream sent
## as it is and any other body as one closed piece (`HTTP.whole`), which the server sends with `Content-Length`.
export def to_stream_response(conn: Conn) -> HTTP.StreamResponse
  problem = refusal(conn)
  if not problem.empty?
    plain = refused(conn, problem)
    return HTTP.StreamResponse(status: plain.status, headers: plain.headers, body: HTTP.whole(plain.body))
  end

  if conn.status == 204 or conn.status == 304
    close_stream(conn)
    return HTTP.StreamResponse(status: conn.status, headers: conn.response_headers, body: HTTP.whole(NO_BODY))
  end

  case conn.response_stream
    some(body) ->
      headers = conn.response_headers
      return HTTP.StreamResponse(status: conn.status, headers: headers, body: body, length: conn.response_length)

    none ->
      whole = HTTP.whole(conn.response_body)
      return HTTP.StreamResponse(status: conn.status, headers: conn.response_headers, body: whole)
  end
end

# The headers of the answer for a test: the `Content-Length` of a stream with a length is added, as the server does.
def sized_headers(conn: Conn) -> List[Header]
  case conn.response_length
    some(length) -> return conn.response_headers.push(Header(name: "content-length", value: length.to_s))
    none -> return conn.response_headers
  end
end

# The conn with no stream: the one it had is closed, since nothing will read it.
def release(conn: Conn) -> Conn
  close_stream(conn)
  return conn.with(response_stream: none, response_length: none)
end

# The plain 500 for a response the server would refuse. A stream that will not be sent is closed.
def refused(conn: Conn, problem: String) -> HttpResponse
  IO.warn("bond: #{conn.method} #{conn.path}: invalid response: #{problem}")
  close_stream(conn)
  return plain_500(INTERNAL_ERROR)
end

def plain_500(body: String) -> HttpResponse
  headers = [Header(name: "content-type", value: "text/plain; charset=utf-8")]
  return HttpResponse(status: 500, headers: headers, body: body.bytes)
end

# The pieces of a stream until the producer closes it, as one `Bytes`. It stops at `max_pieces` pieces (when it is
# above 0) or when `timeout_ms` is spent for the whole body, and then the channel is closed so the producer stops. Each
# wait for a piece is the time that is left, so one gap may take all of it. Only a cut by time is reported on stderr:
# the producer closing is the end and the piece limit was asked for.
def collect(conn: Conn, body: Channel[Bytes], max_pieces: Int, timeout_ms: Int) -> Bytes
  pieces: List[Bytes] = []
  deadline = Time.monotonic_ms() + timeout_ms
  while true
    if max_pieces > 0 and pieces.size >= max_pieces
      body.close
      break
    end

    left = deadline - Time.monotonic_ms()
    if left <= 0
      cut(conn, body)
      break
    end

    case body.recv(left)
      ok(piece) -> pieces = pieces.push(piece)
      error(_) ->
        if not body.closed?
          cut(conn, body)
        end

        break
    end
  end

  return Bytes.concat(pieces)
end

def cut(conn: Conn, body: Channel[Bytes]) -> Void
  IO.warn("bond: #{conn.method} #{conn.path}: the stream took too long, so the body is cut")
  body.close
end

# Why the server would refuse the response, or "" when it would not.
def refusal(conn: Conn) -> String
  if conn.status < 200 or conn.status > 599
    return "the status #{conn.status} is outside 200 to 599"
  end

  case conn.response_length
    some(length) ->
      if length < 0
        return "the length of a stream is negative"
      end

    none -> ""
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
  return digit or upper or lower or TOKEN_SYMBOLS.index_of(ch).some?
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
    some(at) -> return "#{message.slice(0, at)}: #{message.split(": ").last}"
    none -> return message
  end
end
