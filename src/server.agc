## The app on the HTTP server of `std/http`.

import HTTP from "std/http"
import Apps from "app"
import {App} from "app"

## Serves `app` in the background and returns at once. The server belongs to the task that calls this, so call it
## from the task that keeps it, such as `main`. Port 0 picks a free port (`local_port`). It uses the default
## options of `std/http`; `start_with` takes others.
export def start(app: App, host: String, port: Int) -> Result[HttpServer]
  return start_with(app, host, port, HTTP.server_options())
end

## Like `start`, with the options of the server of `std/http` (`HttpServerOptions`: the timeouts, the connections
## at once and the body limit), such as `HTTP.server_options().with(max_body_bytes: 4_194_304)`.
export def start_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[HttpServer]
  handler = answering() do |request| ok(Apps.handle_stream(app, request)) end
  return HTTP.listen_stream(host, port, handler, options)
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
  return run_with(app, host, port, HTTP.server_options())
end

## Like `run`, with the options of `start_with`.
export def run_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[Void]
  server = try start_with(app, host, port, options)
  return wait(server)
end

# `HTTP.listen_stream` takes the handler before its last argument, so a block cannot be written there: this gives
# the block a name first.
def answering(
  handler: Fn[HttpRequest, Result[HTTP.StreamResponse]],
) -> Fn[HttpRequest, Result[HTTP.StreamResponse]]
  return handler
end
