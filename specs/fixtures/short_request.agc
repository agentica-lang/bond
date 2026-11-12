## `Testing.request` with the headers and the body left out, and with the headers only.

import HTTP from "std/http"
import Bond from "../../bond"
import Testing from "../../testing"

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  agent = Bond.request_header(conn, "x-agent").unwrap_or("none")
  ok(Bond.text(conn, 200, "hello #{agent} #{conn.body.size}"))
end

def text_of(response: HTTP.Response) -> String = String.from_bytes(response.body).unwrap!

def main() -> Void
  app = Bond.app() |> Bond.get("/hello", &hello)
  puts(text_of(Testing.request(app, "GET", "/hello")))
  puts(text_of(Testing.request(app, "GET", "/hello", [HTTP.Header(name: "X-Agent", value: "bond")])))
  puts(text_of(Testing.request(app, "GET", "/hello", [], "abc")))
end
