## The app on the HTTP server of `std/http`.

import HTTP from "std/http"
import Apps from "app"
import {App} from "app"

## Serves `app` in the background and returns at once. The server belongs to the task that calls this, so call it
## from the task that keeps it, such as `main`. Port 0 picks a free port (`local_port`).
export def start(app: App, host: String, port: Int) -> Result[HttpServer]
  handler = answering() do |request| ok(Apps.handle(app, request)) end
  return HTTP.listen(host, port, handler, HTTP.server_options())
end

export def start_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[HttpServer]
  return start(app, host, port)
end

export def run_with(app: App, host: String, port: Int, options: HttpServerOptions) -> Result[Void]
  return run(app, host, port)
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
  server = try start(app, host, port)
  return wait(server)
end

# `HTTP.listen` takes the handler before its last argument, so a block cannot be written there: this gives the
# block a name first.
def answering(handler: Fn[HttpRequest, Result[HttpResponse]]) -> Fn[HttpRequest, Result[HttpResponse]]
  return handler
end
