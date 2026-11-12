## The WebSocket client of `websocket.feature`: the package `websocket-client`, which shares no code with Bond or
## `std/http` (the server), so it is an independent peer. It is a program of its own, with its own manifest, so that
## Bond does not depend on the package: a manifest has one list of dependencies, and a user of Bond would fetch it.
##
## Usage: peer.agc PORT PATH MODE TEXT [HEADER...] where a HEADER is `Name: value`. It opens a WebSocket to
## 127.0.0.1:PORT at PATH with the headers and prints one JSON line: the answer of the handshake (`status`, `fields`,
## `body`; a 101 has no body), and, when it is a 101, what the WebSocket did after it:
##   talk   sends TEXT and reads the answer, then closes with a close frame
##   leave  sends TEXT, reads the answer, and drops the socket with no close frame
## `answer` is the text that came back and `close_code` the code of a close frame of the server, which comes first
## when the handler of the route crashed (`answer` is "" then).

import HTTP from "std/http"
import WebSocket from "pkg/websocket-client/websocket"

READ_MS = 5_000

# What the program prints: the one shape of `Talk` in `specs/steps.agc`.
struct Talk
  status: Int
  fields: List[HTTP.Header]
  body: String
  answer: String = ""
  close_code: Int = 0
end

def header_of(text: String) -> HTTP.Header
  at = text.index_of(":").unwrap!
  HTTP.Header(name: text.slice(0, at), value: text.slice(at + 1, text.length - at - 1).strip)
end

# The first message after the handshake: its text, or the code of the close frame that the server sent instead.
def converse(ws: WebSocket.Client, mode: String, text: String) -> Result[Talk]
  try WebSocket.send_text(ws, text)
  case try WebSocket.receive(ws)
    WebSocket.Message.Text(answer) ->
      if mode == "leave"
        TCP.close(ws.socket)
      else
        try WebSocket.close(ws, 1000, "")
      end

      ok(Talk(status: ws.status, fields: ws.headers, body: "", answer: answer))

    WebSocket.Message.Close(code, _) -> ok(Talk(status: ws.status, fields: ws.headers, body: "", close_code: code))
    WebSocket.Message.Binary(_) -> error("the server sent a binary message")
  end
end

def talk(port: Int, path: String, mode: String, text: String, headers: List[HTTP.Header]) -> Result[Talk]
  options = WebSocket.Options(headers: headers, read_timeout_ms: READ_MS)
  case try WebSocket.handshake("ws://127.0.0.1:#{port}#{path}", options)
    WebSocket.Handshake.Refused(status, fields, body) -> ok(Talk(status: status, fields: fields, body: body))
    WebSocket.Handshake.Open(ws) -> converse(ws, mode, text)
  end
end

def main() -> Void
  args = System.args()
  headers = args.drop(4).map do |text| header_of(text) end
  case talk(args[0].to_i!, args[1], args[2], args[3], headers)
    ok(done) -> puts(JSON.encode(done))
    error(reason) -> puts(JSON.encode({"error": reason}))
  end

  IO.flush()
end
