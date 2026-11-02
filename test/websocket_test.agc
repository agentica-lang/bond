import HTTP from "std/http"
import Bond from "../bond"
import Testing from "../testing"

HANDSHAKE = [
  Header(name: "upgrade", value: "websocket"),
  Header(name: "connection", value: "Upgrade"),
  Header(name: "sec-websocket-key", value: "dGhlIHNhbXBsZSBub25jZQ=="),
  Header(name: "sec-websocket-version", value: "13"),
]

def silent(conn: Bond.Conn, socket: HTTP.WebSocket) -> Result[Void]
  return ok()
end

# A login check: a handshake without a token is answered 401 before the route.
def require_token(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/private" and Bond.request_header(conn, "x-token").unwrap_or("") == ""
    return ok(Bond.halt(conn, 401, "login first"))
  end

  return ok(conn)
end

# The headers with the value of `name` replaced.
def replaced(headers: List[Header], name: String, value: String) -> List[Header]
  kept = headers.select do |field| field.name != name end
  return kept.push(Header(name: name, value: value))
end

def app() -> Bond.App
  return (
    Bond.app()
    |> Bond.before(&require_token)
    |> Bond.websocket("/live", &silent)
    |> Bond.websocket("/private", &silent)
  )
end

def main() -> Void
  Test.run([
    Test.test("Testing.request answers an accepted handshake with a 101 and no body") do
      response = Testing.request(app(), "GET", "/live", HANDSHAKE, "")
      try Test.eq(response.status, 101)
      try Test.eq(HTTP.header_values(response.headers, "upgrade"), ["websocket"])
      Test.eq(response.body.size, 0)
    end,
    Test.test("a handshake that std/http refuses is its answer: 400 for a bad key, 426 for another version") do
      bad_key = replaced(HANDSHAKE, "sec-websocket-key", "short")
      try Test.eq(Testing.request(app(), "GET", "/live", bad_key, "").status, 400)
      other = replaced(HANDSHAKE, "sec-websocket-version", "8")
      response = Testing.request(app(), "GET", "/live", other, "")
      try Test.eq(response.status, 426)
      Test.eq(HTTP.header_values(response.headers, "sec-websocket-version"), ["13"])
    end,
    Test.test("a before filter that halts answers the handshake instead") do
      try Test.eq(Testing.request(app(), "GET", "/private", HANDSHAKE, "").status, 401)
      with_token = HANDSHAKE.push(Header(name: "x-token", value: "t"))
      Test.eq(Testing.request(app(), "GET", "/private", with_token, "").status, 101)
    end,
    Test.test("another method of the path is a 405, as for any GET route") do
      Test.eq(Testing.request(app(), "POST", "/live", HANDSHAKE, "").status, 405)
    end,
  ])
end
