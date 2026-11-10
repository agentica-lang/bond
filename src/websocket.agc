## WebSocket routes: a path whose `GET` is a WebSocket handshake, served by the same server as the pages and the
## streams of the app.

import HTTP from "std/http"
import Apps from "app"
import Conns from "conn"
import Csrf from "csrf"
import {App} from "app"
import {Conn} from "conn"

UPGRADE_REQUIRED = 426

## The options of a route that sets none: `std/http`'s, with a ping after 30 s with nothing to send and a peer that is
## silent for 120 s dropped (see `websocket`).
export WEBSOCKET_OPTIONS = HTTP.WebSocketOptions(idle_ms: 120_000, ping_ms: 30_000)

## The function that runs one WebSocket of a `Bond.websocket` route: it gets the `Conn` of the handshake (after the
## `before` filters, with the params of the route and the session) and the `WebSocket` (`std/http`), and returns when
## the WebSocket is done.
export type WebSocketHandler = Fn[Conn, HTTP.WebSocket, Result[Void]]

## Adds a WebSocket route: a `GET` of `pattern` that is a WebSocket handshake is upgraded on the server of the app (a
## page, a stream and a WebSocket share one port), and `handler` runs the WebSocket in a task of its own.
## The `before` filters run first, so a filter that halts answers the handshake instead: a route that needs a login
## checks it there. Then:
##
## 1. A request that does not ask for the upgrade (no `Upgrade: websocket`) is a 426 with `Upgrade: websocket`.
## 2. A handshake from a page of another site is a 403. It passes when it has no `Origin` (not a browser), when its
##    `Origin` is one of `allowed_origins` (as in `Bond.csrf`: `"https://app.example.com"`), or when the host of the
##    `Origin` is the `Host` of the request; an empty `Origin` and two `Origin` headers are refused. Without this check
##    a page on another site could open a WebSocket to the app with the visitor's cookies.
## 3. `HTTP.accept_websocket` checks the handshake with `options`: a bad one is a 400 (a 426 for another version).
##
## The `after` filters run for the handshake too. An accepted one has status 101, and an `after` filter that answers
## something else (`text`, `status`, `halt`, `redirect`) or fails is answered instead, with no upgrade. The headers and
## the body of an accepted handshake are not sent, since the server answers the upgrade: `handler` cannot change the
## session (no response carries the cookie), and the session is checked once, at the handshake. A runtime error in
## `handler` ends that WebSocket (code 1011) and the server goes on; the message goes to stderr. `Testing.request`
## answers an accepted handshake with a 101 and does not run `handler`.
##
## An open WebSocket holds one of the server's `max_connections`, so with no `options` (`none`) a quiet one is dropped
## (`WEBSOCKET_OPTIONS`): the server pings after 30 s with nothing to send (a browser answers every ping by itself, and
## the traffic keeps proxies and NATs, which often drop a connection idle for 60 s, from closing it), and a peer that
## sent nothing for 120 s, not even a pong, is dropped (code 1006 for `handler`).
## `HTTP.WebSocketOptions()` of `std/http` has no such limit. To change one option keep the others:
## `some(Bond.WEBSOCKET_OPTIONS.with(max_message_bytes: 65_536))`.
## The program stops when `pattern` or an allowed origin is bad, or when `options` is out of range.
export def websocket(
  app: App,
  pattern: String,
  handler: WebSocketHandler,
  allowed_origins: List[String] = [],
  options: Optional[HTTP.WebSocketOptions] = none,
) -> App
  chosen = chosen_options(options)
  origins = Csrf.checked_origins(allowed_origins)
  # `accept_websocket` checks the options before the request, so a request with no headers shows a bad option now,
  # at the start; it is no handshake, so its `Reply` is never sent and `idle` never runs.
  probe = HTTP.accept_websocket(
    HttpRequest(method: "GET", target: "/", path: "/", headers: [], body: "".bytes),
    &idle,
    chosen,
  )

  if not probe.ok?
    bad: Result[App] = error("bond: the WebSocket options of #{pattern}: #{probe.message}")
    return bad.unwrap!
  end

  Apps.get(app, pattern) do |conn| handshake(conn, handler, origins, chosen) end
end

## The options of a route: the ones it was given, or `WEBSOCKET_OPTIONS` for `none`. For `websocket` and its test; it
## is not part of `Bond`.
export def chosen_options(options: Optional[HTTP.WebSocketOptions]) -> HTTP.WebSocketOptions
  options.unwrap_or(WEBSOCKET_OPTIONS)
end

def handshake(
  conn: Conn,
  handler: WebSocketHandler,
  origins: List[String],
  options: HTTP.WebSocketOptions,
) -> Result[Conn]
  if not asks_upgrade?(conn)
    upgrade = Conns.header(Conns.header(conn, "upgrade", "websocket"), "connection", "Upgrade")
    return ok(Conns.halt(upgrade, UPGRADE_REQUIRED, "upgrade required"))
  end

  return ok(Conns.halt(conn, 403, "cross-origin WebSocket refused")) if not origin_allowed?(origins, conn)

  request = HttpRequest(
    method: conn.method,
    target: conn.path,
    path: conn.path,
    headers: conn.headers,
    body: conn.body,
    remote_addr: conn.remote_addr,
  )

  session = sessioning() do |socket| run(conn, handler, socket) end
  decided = try HTTP.accept_websocket(request, session, options)
  case decided
    HTTP.Upgrade.Reply(response) ->
      ok(
        conn.with(
          status: response.status,
          response_headers: response.headers,
          response_body: response.body,
          halted: true,
        ),
      )

    HTTP.Upgrade.Accept(_, _, _, _) -> ok(conn.with(status: Conns.SWITCHING, upgrade: some(decided)))
  end
end

# A request asks for the upgrade when a value of its `Upgrade` header lists `websocket` (any case).
def asks_upgrade?(conn: Conn) -> Bool
  values = HTTP.header_values(conn.headers, "upgrade")
  values.any? do |value| value.split(",").any? do |token| token.strip.downcase == "websocket" end end
end

# The rule of `websocket` for `Origin`: a request with none passes (a browser always sends it with a handshake), and
# one with an `Origin` passes when it is allowed or names the host of the request. An empty `Origin`, which no browser
# sends, is refused.
def origin_allowed?(origins: List[String], conn: Conn) -> Bool
  return false if Csrf.repeated?(conn, "origin")

  case Conns.request_header(conn, "origin")
    error(_) -> true
    ok(value) ->
      origin = value.downcase
      origin != "" and (origins.any? do |allowed| allowed == origin end or Csrf.host_origin?(origin, conn))
  end
end

# The handler runs in a task of its own, as the handlers of the routes do, so that a runtime error ends the WebSocket
# and not the server's connection task; its `error` closes the WebSocket with 1011.
def run(conn: Conn, handler: WebSocketHandler, socket: HTTP.WebSocket) -> Result[Void]
  task = Task.spawn() do handler.call(conn, socket) end
  case Task.await(task)
    ok(_) -> ok()
    error(message) ->
      IO.warn("bond: #{conn.method} #{conn.path}: the WebSocket ended with an error: #{message}")
      error(message)
  end
end

# `HTTP.accept_websocket` takes the session before its last argument, so a block cannot be written there: this gives
# the block a name first.
def sessioning(session: HTTP.WebSocketSession) -> HTTP.WebSocketSession = session

# The session of the handshake that checks the options when the route is added; it never runs.
def idle(socket: HTTP.WebSocket) -> Result[Void] = ok()
