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
import HTTP from "std/http"
import {App} from "src/app"

## Sends the request to `app` and gives the response. `target` is the path with its query, as a client sends it
## (`/todos?done=1`); header names are lowercased, as the server does. `headers` default to none and `body` to an
## empty text; `request_bytes` takes the body as `Bytes`, for a request that is not text.
##
## A streamed body (`Bond.stream`, `Bond.sse`) is read here until the producer closes the channel, `max_pieces` pieces
## (0, the default, is no limit) or `timeout_ms` for the whole body (10 s by default; one gap between pieces may take
## all of it); then the channel is closed, so a producer that never ends stops. A body cut by the time says so on
## stderr. A `HEAD` gets no body. The body of the response is `Bytes`, whatever it holds (`HTTP.text` reads text).
export def request(
  app: App,
  method: String,
  target: String,
  headers: List[Header] = [],
  body: String = "",
  max_pieces: Int = 0,
  timeout_ms: Int = 10_000, # keep in sync with Conns.to_response, Apps.handle and specs/steps.agc
) -> HttpResponse
  return request_bytes(app, method, target, headers, body.bytes, max_pieces, timeout_ms)
end

## The body of `response` as text: UTF-8 only, and a `charset` other than `utf-8` is an error, as `HTTP.text` has it.
export def text(response: HttpResponse) -> Result[String]
  return HTTP.text(response.body, response.headers)
end

## Like `request`, with the body as `Bytes` (so `headers` come before it and have no default). The rules and the
## response are those of `request`.
export def request_bytes(
  app: App,
  method: String,
  target: String,
  headers: List[Header],
  body: Bytes,
  max_pieces: Int = 0,
  timeout_ms: Int = 10_000, # keep in sync with Conns.to_response, Apps.handle and specs/steps.agc
) -> HttpResponse
  path = target
  case target.index_of("?")
    some(at) -> path = target.slice(0, at)
    none -> path = target
  end

  lowered = headers.map do |header| Header(name: header.name.downcase, value: header.value) end
  request = HttpRequest(method: method, target: target, path: path, headers: lowered, body: body)
  return Apps.handle(app, request, max_pieces, timeout_ms)
end
