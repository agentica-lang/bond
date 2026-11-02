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

# After the route: `/closed` is answered 403 by the filter, and `/broken` makes it fail.
def overrule(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/closed"
    return ok(Bond.text(conn, 403, "closed for maintenance"))
  end

  if conn.path == "/broken"
    return error("the after filter failed")
  end

  return ok(conn)
end

# A filter that changes the session of every request, so the answer of a page would carry the cookie.
def remember(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.set_session(conn, "seen", "yes"))
end

def app() -> Bond.App
  return (
    Bond.app()
    |> Bond.before(&require_token)
    |> Bond.after(&overrule)
    |> Bond.websocket("/live", &silent)
    |> Bond.websocket("/private", &silent)
    |> Bond.websocket("/closed", &silent)
    |> Bond.websocket("/broken", &silent)
  )
end

def sessions_app() -> Bond.App
  return (
    Bond.app()
    |> Bond.sessions(Bond.SessionOptions(secret: "a secret of at least thirty-two bytes!!"))
    |> Bond.before(&remember)
    |> Bond.websocket("/live", &silent)
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
    Test.test("an after filter that answers something else is sent, with no upgrade") do
      response = Testing.request(app(), "GET", "/closed", HANDSHAKE, "")
      try Test.eq(response.status, 403)
      try Test.eq(HTTP.header_values(response.headers, "upgrade"), [])
      Test.eq(Testing.text(response).unwrap!, "closed for maintenance")
    end,
    Test.test("an after filter that fails is a 500, with no upgrade") do
      response = Testing.request(app(), "GET", "/broken", HANDSHAKE, "")
      try Test.eq(response.status, 500)
      Test.eq(HTTP.header_values(response.headers, "upgrade"), [])
    end,
    Test.test("an empty Origin and two Origin headers are refused") do
      empty = HANDSHAKE.push(Header(name: "origin", value: ""))
      try Test.eq(Testing.request(app(), "GET", "/live", empty, "").status, 403)
      host = Header(name: "host", value: "example.com")
      same = Header(name: "origin", value: "http://example.com")
      try Test.eq(Testing.request(app(), "GET", "/live", HANDSHAKE.concat([host, same]), "").status, 101)
      twice = HANDSHAKE.concat([host, same, same])
      Test.eq(Testing.request(app(), "GET", "/live", twice, "").status, 403)
    end,
    Test.test("the 101 carries no Set-Cookie, even when a before filter changed the session") do
      response = Testing.request(sessions_app(), "GET", "/live", HANDSHAKE, "")
      try Test.eq(response.status, 101)
      Test.eq(HTTP.header_values(response.headers, "set-cookie"), [])
    end,
    Test.test("another method of the path is a 405, as for any GET route") do
      Test.eq(Testing.request(app(), "POST", "/live", HANDSHAKE, "").status, 405)
    end,
  ])
end
