---
title: WebSockets
weight: 16
description: A WebSocket route on the same port as the pages and the streams, with the Origin check.
---

# WebSockets

`Bond.websocket(app, pattern, handler)` adds a route whose `GET` is a WebSocket handshake. The server of `Bond.run` upgrades it and runs `handler` on the connection, so a page, a stream and a WebSocket share one port. The handler gets the `Conn` of the handshake (with the params of the route and the session that the `before` filters loaded) and the `HTTP.WebSocket` of `std/http`: messages from the browser arrive on `socket.incoming`, and the messages to send go on `socket.outgoing`. It returns when the WebSocket is done, and the server closes it with code 1000 (1011 for an `error`).

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

A session must keep taking messages from `incoming` until the `Close` message (or end): while it does not, the server stops reading the socket. `HTTP.WebSocketOptions` (the last argument, `options`) sets the largest message, the idle time, the pings and the subprotocols; see the network page of the Agentica library.

## What the route answers

The `before` filters run first, so a filter that halts (a login check) answers the handshake instead. Then:

1. A request that does not ask for the upgrade (a page load, `curl` with no `Upgrade: websocket`) is a 426 Upgrade Required with `Upgrade: websocket`. Another method of the path is a 405, as for any `GET` route.
2. A handshake from a page of another site is a 403 (see below).
3. `std/http` checks the handshake: a bad one is a 400, and one of another WebSocket version a 426 with `Sec-WebSocket-Version: 13`.

The `after` filters run for the handshake too. An accepted handshake has status 101, but its headers and body are not sent, since the server answers the upgrade itself. So a change to the session in a WebSocket handler is not saved: no response carries the cookie. A runtime error in the handler closes its WebSocket with 1011, writes the message to stderr, and the server goes on.

## The Origin check

A browser lets any page open a WebSocket to any site, and sends the cookies of that site with the handshake. So a page on `evil.test` could talk to your app as its visitor. The browser says which page asks in `Origin`, and the route checks it:

- a handshake whose `Origin` names the host of the request (the part after `://` is the `Host` header) passes;
- so does one whose `Origin` is one of `allowed_origins`, origins as a browser writes them, as in [`Bond.csrf`](/guide/csrf/): `Bond.websocket(app, "/live", &live, ["https://app.example.com"])`;
- a handshake with no `Origin` passes: a browser always sends it, so this is a tool or a server, which another page cannot use;
- anything else is a 403, `Origin: null` and two `Origin` headers too.

The scheme is not compared, since the server may sit behind a proxy that ends TLS. The program stops when an allowed origin is one a browser never sends, or when `options` is out of range.

## Testing

`Testing.request` answers an accepted handshake with a 101 and `Upgrade: websocket`, and does not run the handler, since it has no socket. Test the refusals (426, 403, 400) the same way, and the conversation over a socket.

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
    Header(name: "upgrade", value: "websocket"),
    Header(name: "connection", value: "Upgrade"),
    Header(name: "sec-websocket-key", value: "dGhlIHNhbXBsZSBub25jZQ=="),
    Header(name: "sec-websocket-version", value: "13"),
  ]
  puts(Testing.request(app, "GET", "/live", handshake).status)
  puts(Testing.request(app, "GET", "/live").status)
  cross = handshake.push(Header(name: "origin", value: "https://evil.test"))
  puts(Testing.request(app, "GET", "/live", cross).status)
end
```

```output
101
426
403
```
