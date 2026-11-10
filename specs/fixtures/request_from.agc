## `Testing.request_from`: the handler sees the address that the test chose, and the headers and the body are optional.

import Bond from "../../bond"
import Testing from "../../testing"

def who(conn: Bond.Conn) -> Result[Bond.Conn]
  agent = Bond.request_header(conn, "x-agent").unwrap_or("none")
  ok(Bond.text(conn, 200, "#{conn.remote_addr} #{agent} #{conn.body.size}"))
end

def text_of(response: HttpResponse) -> String = String.from_bytes(response.body).unwrap!

def main() -> Void
  app = Bond.app() |> Bond.get("/who", &who)
  puts(text_of(Testing.request_from(app, "203.0.113.9", "GET", "/who")))
  puts(text_of(Testing.request_from(app, "::1", "GET", "/who", [Header(name: "X-Agent", value: "bond")])))
  puts(text_of(Testing.request_from(app, "198.51.100.7", "GET", "/who", [], "abc")))
  puts(text_of(Testing.request(app, "GET", "/who")))
end
