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
import {App} from "src/app"

## Sends the request to `app` and gives the response. `target` is the path with its query, as a client sends it
## (`/todos?done=1`); header names are lowercased, as the server does. `headers` default to none and `body` to an
## empty text.
##
## A streamed body (`Bond.stream`, `Bond.sse`) is read here until the producer closes the channel, `max_pieces` pieces
## (0, the default, is no limit) or `timeout_ms` for the whole body (10 s by default; one gap between pieces may take
## all of it); then the channel is closed, so a producer that never ends stops. A body cut by the time says so on
## stderr. A `HEAD` gets no body. The stream must be UTF-8 text: any other is a 500 whose body is `the stream is not
## UTF-8 text`.
export def request(
  app: App,
  method: String,
  target: String,
  headers: List[Header] = [],
  body: String = "",
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
