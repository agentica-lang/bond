---
title: WebSockets
weight: 17
description: A WebSocket route on the same port as the pages and the streams, with the Origin check.
---

# WebSockets

`Bond.websocket(app, pattern, handler)` adds a route whose `GET` is a WebSocket handshake. The server of `Bond.run` upgrades it and runs `handler` on the connection, so a page, a stream and a WebSocket share one port. The handler gets the `Conn` of the handshake (with the route params and the session that the `before` filters loaded) and the `HTTP.WebSocket` of `std/http`: messages from the browser arrive on `socket.incoming`, and messages to send go on `socket.outgoing`. It returns when the WebSocket is done, and the server closes it with code 1000 (1011 for an `error`).

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"

def page(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 200, "<script>new WebSocket(`ws://${location.host}/rooms/lobby`)</script>"))
end

def room(conn: Bond.Conn, socket: HTTP.WebSocket) -> Result[Void]
  name = try Bond.param(conn, "name")
  while true
    case socket.incoming.recv(60_000)
      ok(message) ->
        case message
          HTTP.Message.Text(text) -> try socket.outgoing.send(HTTP.Message.Text("#{name}: #{text}"), 5000)
          HTTP.Message.Close(_, _) -> return ok()
          _ -> next
        end

      error(_) -> return ok()
    end
  end

  return ok()
end

def main() -> Void
  app = Bond.app() |> Bond.get("/", &page) |> Bond.websocket("/rooms/:name", &room)
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

The handler must keep taking messages from `incoming` until the `Close` message (or end): while it does not, the server stops reading the socket.

## Open sockets and the options

An open WebSocket holds one of the server's connections until it closes, and the server serves at most `max_connections` at once (128 by default, an option of [`Bond.start_with`](/guide/server/#options)), so quiet sockets would starve the other routes. With no `options`, a route uses `Bond.WEBSOCKET_OPTIONS`:

- `ping_ms: 30_000`: after 30 s with nothing to send, the server sends a ping, which a browser answers by itself; the traffic keeps proxies and NATs (which often drop a connection idle for 60 s) from closing it.
- `idle_ms: 120_000`: a peer that sent nothing for 120 s, not even a pong, is dropped, and the handler gets `Close` with code 1006.

The rest are the defaults of `HTTP.WebSocketOptions` of `std/http` (whose own `idle_ms` is no limit): `max_message_bytes` (1 MiB), `close_ms` and `protocols`. The last argument of `Bond.websocket` is an `Optional` that changes them; start from `Bond.WEBSOCKET_OPTIONS` to keep the bounds: `Bond.websocket(app, "/live", &live, [], some(Bond.WEBSOCKET_OPTIONS.with(max_message_bytes: 65_536)))` (a bare `HTTP.WebSocketOptions(...)` is a type error). Raise `max_connections` for an app that keeps many sockets open.

## What the route answers

The `before` filters run first, so a filter that halts answers the handshake instead (check a login there, as for a page). Then:

1. A request that does not ask for the upgrade (a page load, `curl` with no `Upgrade: websocket`) is a 426 Upgrade Required with `Upgrade: websocket`. Another method of the path is a 405, as for any `GET` route.
2. A handshake from a page of another site is a 403 (see below).
3. `std/http` checks the handshake: a bad one is a 400, and one of another WebSocket version a 426 with `Sec-WebSocket-Version: 13`.

The `after` filters run for the handshake too. An accepted handshake has status 101; an `after` filter that answers something else or fails is sent instead, and the WebSocket never starts. A runtime error in the handler closes its WebSocket with 1011, writes the message to stderr, and the server goes on.

## The session

The handler cannot change the session: the server answers the upgrade itself and sends no header of an accepted handshake. Change it in a normal request, before the page opens the socket. The session is checked once, at the handshake, so a WebSocket stays open after its visitor logs out: a long handler that must stop checks again, or relies on `idle_ms` for a quiet socket.

## The Origin check

A browser lets any page open a WebSocket to any site, with the cookies of that site, so a page on `evil.test` could talk to your app as its visitor. The route checks the `Origin` that the browser sends:

- a handshake whose `Origin` names the host of the request (the part after `://` is the `Host` header) passes;
- so does one whose `Origin` is one of `allowed_origins`, written as in [`Bond.csrf`](/guide/csrf/): `Bond.websocket(app, "/live", &live, ["https://app.example.com"])`;
- a handshake with no `Origin` passes: a browser always sends it, so this is a tool or a server;
- anything else is a 403, `Origin: null`, an empty `Origin` and two `Origin` headers too.

The scheme is not compared, since the server may sit behind a proxy that ends TLS. A check of `Origin` against `Host` does not stop DNS rebinding: a page of `evil.test` whose name then points to `127.0.0.1` sends `Origin: http://evil.test` and `Host: evil.test`, which match. An app on a local address with no login should refuse a `Host` that is not its own, in a `before` filter. The program stops when an allowed origin is one a browser never sends, or when `options` is out of range.

## Testing

`Testing.request` answers an accepted handshake with a 101 and `Upgrade: websocket`, and does not run the handler, since it has no socket. Test the refusals (426, 403, 400) the same way; the conversation over a socket needs a real one (`specs/websocket.feature`).

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def live(conn: Bond.Conn, socket: HTTP.WebSocket) -> Result[Void]
  return ok()
end

def main() -> Void
  app = Bond.app() |> Bond.websocket("/live", &live)
  handshake = [
    HTTP.Header(name: "upgrade", value: "websocket"),
    HTTP.Header(name: "connection", value: "Upgrade"),
    HTTP.Header(name: "sec-websocket-key", value: "dGhlIHNhbXBsZSBub25jZQ=="),
    HTTP.Header(name: "sec-websocket-version", value: "13"),
  ]
  puts(Testing.request(app, "GET", "/live", handshake).status)
  puts(Testing.request(app, "GET", "/live").status)
  cross = handshake.push(HTTP.Header(name: "origin", value: "https://evil.test"))
  puts(Testing.request(app, "GET", "/live", cross).status)
end
```

```output
101
426
403
```
