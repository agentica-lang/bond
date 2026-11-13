## Runs an app in process, with no socket: the request goes through the same filters and routes as one that came
## over `Bond.run`.
##
## ```ruby
## import Testing from "pkg/bond/testing"
##
## response = Testing.request(app, "POST", "/todos", [], "buy milk")
## ping = Testing.request(app, "GET", "/ping")
## ```

import Apps from "src/app"
import Uploads from "src/uploads"
import Sessions from "src/session"
import HTTP from "std/http"
import {App} from "src/app"
import {SessionOptions} from "src/session"

## The client address of a request that does not choose one: `Conn.remote_addr` of the requests of `request`.
LOOPBACK = "127.0.0.1"

## Sends the request to `app` and gives the response. `target` is the path with its query, as a client sends it
## (`/todos?done=1`); header names are lowercased, as the server does. `headers` default to none and `body` to an
## empty text; `request_bytes` takes the body as `Bytes`, for a request that is not text.
##
## A streamed body (`Bond.stream`, `Bond.sse`) is read here until the producer closes the channel, `max_pieces` pieces
## (0, the default, is no limit) or `timeout_ms` for the whole body (10 s by default; one gap between pieces may take
## all of it); then the channel is closed, so a producer that never ends stops. A body cut by the time says so on
## stderr. A `HEAD` of a streamed body or of a sent file gets no body. The body of the response is `Bytes`, whatever it holds (`HTTP.text` reads text).
##
## With `Bond.uploads`, a `multipart/form-data` body is read as the server reads it (in pieces of 64 KiB, after the
## before filters): its files are saved, given to the handler and removed after the answer, and a body over a limit is
## the same 413.
##
## `remote_addr` is the client address the handler sees in `conn.remote_addr` (`LOOPBACK` by default); to choose one,
## `request_from` is shorter.
def request(
  app: App,
  method: String,
  target: String,
  headers: List[HTTP.Header] = [],
  body: String = "",
  max_pieces: Int = 0,
  timeout_ms: Int = TIMEOUT_MS,
  remote_addr: String = LOOPBACK,
) -> HTTP.Response
  send(app, method, target, headers, body.bytes, max_pieces, timeout_ms, remote_addr)
end

## Like `request`, as the client at `remote_addr` (what the handler reads in `conn.remote_addr`, as the server fills it
## from the peer of the socket): `Testing.request_from(app, "203.0.113.9", "GET", "/")`. The address comes first and
## the stream bounds keep their defaults; a test that needs other bounds uses `request`.
def request_from(
  app: App,
  remote_addr: String,
  method: String,
  target: String,
  headers: List[HTTP.Header] = [],
  body: String = "",
) -> HTTP.Response
  send(app, method, target, headers, body.bytes, 0, TIMEOUT_MS, remote_addr)
end

## The body of `response` as text: UTF-8 only, and a `charset` other than `utf-8` is an error, as `HTTP.text` has it.
def text(response: HTTP.Response) -> Result[String] = HTTP.text(response.body, response.headers)

## Like `request`, with the body as `Bytes` (so `headers` come before it and have no default). The rules and the
## response are those of `request`.
def request_bytes(
  app: App,
  method: String,
  target: String,
  headers: List[HTTP.Header],
  body: Bytes,
  max_pieces: Int = 0,
  timeout_ms: Int = TIMEOUT_MS,
  remote_addr: String = LOOPBACK,
) -> HTTP.Response
  send(app, method, target, headers, body, max_pieces, timeout_ms, remote_addr)
end

## The `Cookie` header value of a request that has a session with `data`, signed as `Bond.sessions(app, options)` would
## sign it (`_bond_session=...`, for `options.name`): `[HTTP.Header(name: "cookie", value: cookie)]` is a request of a
## visitor who is logged in, with no round trip to a login route. The options are not checked as `sessions` checks
## them (a short secret and a negative `max_age` are accepted, so a test can make an expired cookie). An `error` when
## the session is over the size of a cookie.
def session_cookie(options: SessionOptions, data: Map[String, String]) -> Result[String]
  value = try Sessions.seal(options, data)
  ok("#{options.name}=#{value}")
end

private

TIMEOUT_MS = 10_000 # keep in sync with Conns.to_response, Apps.handle and specs/steps.agc

# The core of every request: the filters and routes of `Apps.handle`, or the reading of `Uploads.handle`.
def send(
  app: App,
  method: String,
  target: String,
  headers: List[HTTP.Header],
  body: Bytes,
  max_pieces: Int,
  timeout_ms: Int,
  remote_addr: String,
) -> HTTP.Response
  path = target
  case target.index_of("?")
    some(at) -> path = target.slice(0, at)
    none -> path = target
  end

  lowered = headers.map do |header| HTTP.Header(name: header.name.downcase, value: header.value) end
  request = HTTP.Request(
    method: method,
    target: target,
    path: path,
    headers: lowered,
    body: body,
    remote_addr: remote_addr,
  )

  case Uploads.applies(app, request)
    some(options) -> Uploads.handle(app, options, request, max_pieces, timeout_ms)
    none -> Apps.handle(app, request, max_pieces, timeout_ms)
  end
end
