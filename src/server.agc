## The app on the HTTP server of `std/http`.

import HTTP from "std/http"
import Apps from "app"
import Uploads from "uploads"
import {App} from "app"
import {Conn} from "conn"

## Serves `app` in the background and returns at once. The server belongs to the task that calls this, so call it
## from the task that keeps it, such as `main`. Port 0 picks a free port (`local_port`). It uses the default
## options of `std/http`; `start_with` takes others.
def start(app: App, host: String, port: Int) -> Result[HTTP.Server] = start_with(app, host, port, HTTP.ServerOptions())

## Like `start`, with the options of the server of `std/http` (`HTTP.ServerOptions`: the timeouts, the connections
## at once and the body limit), such as `HTTP.ServerOptions(max_body_bytes: 4_194_304)`.
## With `Bond.uploads`, the server takes a `multipart/form-data` body up to the `max_total_bytes` of the uploads, and
## the other bodies keep `max_body_bytes`.
def start_with(app: App, host: String, port: Int, options: HTTP.ServerOptions) -> Result[HTTP.Server]
  limit = options.max_body_bytes
  served = serving do |request, body| answer(app, limit, request, body) end
  HTTP.serve(host, port, served, options.with(max_body_bytes: Uploads.server_limit(app, limit)))
end

def local_port(server: HTTP.Server) -> Int = HTTP.local_port(server)

## Waits until the server is closed.
def wait(server: HTTP.Server) -> Result[Void] = HTTP.wait(server)

def stop(server: HTTP.Server) -> Void
  HTTP.close_server(server)
end

## Serves `app` and waits: it returns only when the server closes or fails to start.
def run(app: App, host: String, port: Int) -> Result[Void] = run_with(app, host, port, HTTP.ServerOptions())

## Like `run`, with the options of `start_with`.
def run_with(app: App, host: String, port: Int, options: HTTP.ServerOptions) -> Result[Void]
  server = try start_with(app, host, port, options)
  wait(server)
end

private

# The `before` filters and the route lookup run on the head alone; the body is read whole only for a request that goes
# on to its handler, as the app of Bond takes the request whole (`Conn` has the body as bytes). A request that a filter
# halts, or that has no route, is answered without its body, and the connection closes after the answer. A body that is
# over `limit`, or that did not arrive whole, is a 413, 431 or 400 that closes the connection, and the handler is not
# called. The answer is the upgrade of a WebSocket route, or a stream: a body sent in pieces is sent as it is, and any
# other is one closed piece with `Content-Length`.
#
# A `multipart/form-data` body of an app with uploads is read as it arrives instead (`Uploads.answer`).
def answer(app: App, limit: Int, request: HTTP.Request, body: HTTP.RequestBody) -> Result[HTTP.Answer]
  case Uploads.applies(app, request)
    some(options) -> return ok(Uploads.answer(app, options, request, body))
    none -> nil
  end

  ok(Apps.handle_answer_with(app, request.with(body: "".bytes)) do |conn| read(conn, limit, body) end)
end

def read(conn: Conn, limit: Int, body: HTTP.RequestBody) -> Result[Conn]
  case HTTP.read_all(body, limit)
    ok(data) -> ok(conn.with(body: data))
    error(e) -> error(Uploads.refusal_status(e))
  end
end

# `HTTP.serve` takes the app before its last argument, so a block cannot be written there: this gives the block a
# name first.
def serving(app: HTTP.App) -> HTTP.App = app
