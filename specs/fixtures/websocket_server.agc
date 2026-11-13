## The program of `websocket.feature`: a page, a stream and a WebSocket route of one app on 127.0.0.1 and a free port.
## It says the port on its first line. The WebSocket of `/chat/:room` answers each text message with the room and the
## text, and the text `crash` makes its handler crash; when the WebSocket ends, the handler prints `closed`, the room
## and the code. A page of https://app.example.com may open it too. `/quiet/:room` is the same WebSocket with small
## options: a ping after 300 ms with nothing to send, and a peer silent for 1 s is dropped.

import HTTP from "std/http"
import Bond from "../../bond"

private

SEND_MS = 5_000

IDLE_MS = 10_000

def hello(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "hello"))

def ticks(conn: Bond.Conn) -> Result[Bond.Conn]
  pieces: Channel[Bytes] = Channel.new(2)
  try pieces.send("one ".bytes, SEND_MS)
  try pieces.send("two".bytes, SEND_MS)
  pieces.close
  ok(Bond.stream(conn, 200, pieces))
end

def chat(conn: Bond.Conn, socket: HTTP.WebSocket) -> Result[Void]
  room = try Bond.param(conn, "room")
  while true
    case socket.incoming.recv(IDLE_MS)
      ok(message) ->
        case message
          HTTP.Message.Text(text) ->
            if text == "crash"
              puts(1 / (text.length - 5))
            end

            try socket.outgoing.send(HTTP.Message.Text("#{room}: #{text}"), SEND_MS)

          HTTP.Message.Close(code, _) ->
            puts("closed #{room} #{code}")
            IO.flush()
            return ok()
          _ -> next
        end

      error(_) -> return ok()
    end
  end

  ok()
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/hello", &hello)
    |> Bond.get("/ticks", &ticks)
    |> Bond.websocket("/chat/:room", &chat, ["https://app.example.com"])
    |> Bond.websocket("/quiet/:room", &chat, [], some(HTTP.WebSocketOptions(idle_ms: 1_000, ping_ms: 300)))
  )

  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
