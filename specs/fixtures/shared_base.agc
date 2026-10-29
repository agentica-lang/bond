## One app is the base of two others. Adding a route returns a new app, so neither sees the route of the other.

import Bond from "../../bond"
import Testing from "../../testing"

def one(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "one"))
end

def status(app: Bond.App, path: String) -> Int
  return Testing.request(app, "GET", path).status
end

def main() -> Void
  base = Bond.app() |> Bond.get("/base", &one)
  a = base |> Bond.get("/a", &one)
  b = base |> Bond.get("/b", &one)
  puts("a: #{status(a, "/a")} #{status(a, "/b")}")
  puts("b: #{status(b, "/a")} #{status(b, "/b")}")
end
