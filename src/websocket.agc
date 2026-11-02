## WebSocket routes: a path whose `GET` is a WebSocket handshake, served by the same server as the pages and the
## streams of the app.

import HTTP from "std/http"
import Apps from "app"
import Conns from "conn"
import Csrf from "csrf"
import {App} from "app"
import {Conn} from "conn"

UPGRADE_REQUIRED = 426

## The function that runs one WebSocket of a `Bond.websocket` route: it gets the `Conn` of the handshake (after the
## `before` filters, with the params of the route and the session) and the `WebSocket` (`std/http`), and returns when
## the WebSocket is done.
export type WebSocketHandler = Fn[Conn, HTTP.WebSocket, Result[Void]]

## Adds a WebSocket route: a `GET` of `pattern` that is a WebSocket handshake is upgraded on the server of the app (a
## page, a stream and a WebSocket share one port), and `handler` runs the WebSocket in a task of its own.
## The `before` filters run first, so a filter that halts (a login check) answers the handshake instead. Then:
##
## 1. A request that does not ask for the upgrade (no `Upgrade: websocket`) is a 426 with `Upgrade: websocket`.
## 2. A handshake from a page of another site is a 403. It passes when it has no `Origin` (not a browser), when its
##    `Origin` is one of `allowed_origins` (as in `Bond.csrf`: `"https://app.example.com"`), or when the host of the
##    `Origin` is the `Host` of the request; two `Origin` headers are refused. Without this check a page on another
##    site could open a WebSocket to the app with the visitor's cookies.
## 3. `HTTP.accept_websocket` checks the handshake with `options`: a bad one is a 400 (a 426 for another version).
##
## The `after` filters run for the handshake too; an accepted one has status 101, and its headers and body are not
## sent, since the server answers the upgrade. So a change to the session in `handler` is not saved: there is no
## response to carry the cookie. A runtime error in `handler` ends that WebSocket (code 1011) and the server goes on;
## the message goes to stderr. `Testing.request` answers an accepted handshake with a 101 and does not run `handler`.
## The program stops when `pattern` or an allowed origin is bad, or when `options` is out of range.
export def websocket(
  app: App,
  pattern: String,
  handler: WebSocketHandler,
  allowed_origins: List[String] = [],
  options: HTTP.WebSocketOptions = HTTP.WebSocketOptions(),
) -> App
  origins = Csrf.checked_origins(allowed_origins)
  probe = HTTP.accept_websocket(
    HttpRequest(method: "GET", target: "/", path: "/", headers: [], body: "".bytes),
    &idle,
    options,
  )
  if not probe.ok?
    bad: Result[App] = error("bond: the WebSocket options of #{pattern}: #{probe.message}")
    return bad.unwrap!
  end

  return Apps.get(app, pattern) do |conn| handshake(conn, handler, origins, options) end
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

  if not origin_allowed?(origins, conn)
    return ok(Conns.halt(conn, 403, "cross-origin WebSocket refused"))
  end

  request = HttpRequest(
    method: conn.method,
    target: conn.path,
    path: conn.path,
    headers: conn.headers,
    body: conn.body,
  )
  session = sessioning() do |socket| run(conn, handler, socket) end
  decided = try HTTP.accept_websocket(request, session, options)
  case decided
    HTTP.Upgrade.Reply(response) ->
      return ok(
        conn.with(
          status: response.status,
          response_headers: response.headers,
          response_body: response.body,
          halted: true,
        ),
      )

    HTTP.Upgrade.Accept(_, _, _, _) -> return ok(conn.with(status: 101, upgrade: some(decided)))
  end
end

# A request asks for the upgrade when a value of its `Upgrade` header lists `websocket` (any case).
def asks_upgrade?(conn: Conn) -> Bool
  values = HTTP.header_values(conn.headers, "upgrade")
  return values.any? do |value| value.split(",").any? do |token| token.strip.downcase == "websocket" end end
end

# The rule of `websocket` for `Origin`: a request with none passes (a browser always sends it with a handshake), and
# one with an `Origin` passes when it is allowed or names the host of the request.
def origin_allowed?(origins: List[String], conn: Conn) -> Bool
  if Csrf.repeated?(conn, "origin")
    return false
  end

  origin = Conns.request_header(conn, "origin").unwrap_or("").downcase
  if origin == ""
    return true
  end

  return origins.any? do |allowed| allowed == origin end or Csrf.host_origin?(origin, conn)
end

# The handler runs in a task of its own, as the handlers of the routes do, so that a runtime error ends the WebSocket
# and not the server's connection task; its `error` closes the WebSocket with 1011.
def run(conn: Conn, handler: WebSocketHandler, socket: HTTP.WebSocket) -> Result[Void]
  task = Task.spawn() do handler.call(conn, socket) end
  case Task.await(task)
    ok(_) -> return ok()
    error(message) ->
      IO.warn("bond: #{conn.method} #{conn.path}: the WebSocket ended with an error: #{message}")
      return error(message)
  end
end

# `HTTP.accept_websocket` takes the session before its last argument, so a block cannot be written there: this gives
# the block a name first.
def sessioning(session: HTTP.WebSocketSession) -> HTTP.WebSocketSession
  return session
end

# The session of the handshake that checks the options when the route is added; it never runs.
def idle(socket: HTTP.WebSocket) -> Result[Void]
  return ok()
end
