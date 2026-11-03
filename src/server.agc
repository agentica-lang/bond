## The app on the HTTP server of `std/http`.

import HTTP from "std/http"
import Apps from "app"
import Uploads from "uploads"
import {App} from "app"

## Serves `app` in the background and returns at once. The server belongs to the task that calls this, so call it
## from the task that keeps it, such as `main`. Port 0 picks a free port (`local_port`). It uses the default
## options of `std/http`; `start_with` takes others.
export def start(app: App, host: String, port: Int) -> Result[HttpServer]
  return start_with(app, host, port, HttpServerOptions())
end

## Like `start`, with the options of the server of `std/http` (`HttpServerOptions`: the timeouts, the connections
## at once and the body limit), such as `HttpServerOptions(max_body_bytes: 4_194_304)`.
## With `Bond.uploads`, the server takes a `multipart/form-data` body up to the `max_total_bytes` of the uploads, and
## the other bodies keep `max_body_bytes`.
export def start_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[HttpServer]
  limit = options.max_body_bytes
  served = serving() do |request, body| answer(app, limit, request, body) end
  return HTTP.serve(host, port, served, options.with(max_body_bytes: Uploads.server_limit(app, limit)))
end

export def local_port(server: HttpServer) -> Int
  return HTTP.local_port(server)
end

## Waits until the server is closed.
export def wait(server: HttpServer) -> Result[Void]
  return HTTP.wait(server)
end

export def stop(server: HttpServer) -> Void
  HTTP.close_server(server)
end

## Serves `app` and waits: it returns only when the server closes or fails to start.
export def run(app: App, host: String, port: Int) -> Result[Void]
  return run_with(app, host, port, HttpServerOptions())
end

## Like `run`, with the options of `start_with`.
export def run_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[Void]
  server = try start_with(app, host, port, options)
  return wait(server)
end

# The body is read whole before the app runs, as the app of Bond takes the request whole (`Conn` has the body as
# bytes). A body that is over `limit`, or that did not arrive whole, is answered by `HTTP.body_refusal` (413, 431 or
# 400, and the connection closes) and the app is not called. The answer is the upgrade of a WebSocket route, or a
# stream: a body sent in pieces is sent as it is, and any other is one closed piece with `Content-Length`. The body is
# read whole first, so the server accepts an upgrade (it refuses one before the body of the request was read).
#
# A `multipart/form-data` body of an app with uploads is read as it arrives instead (`Uploads.answer`).
def answer(app: App, limit: Int, request: HttpRequest, body: HTTP.RequestBody) -> Result[HTTP.Answer]
  case Uploads.applies(app, request)
    some(options) -> return ok(Uploads.answer(app, options, request, body))
    none -> nil
  end

  case HTTP.read_all(body, limit)
    ok(data) -> return ok(Apps.handle_answer(app, request.with(body: data)))
    error(message) -> return ok(HTTP.body_refusal(message))
  end
end

# `HTTP.serve` takes the app before its last argument, so a block cannot be written there: this gives the block a
# name first.
def serving(app: HTTP.App) -> HTTP.App
  return app
end
