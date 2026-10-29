## A path of 5000 segments against an app with a few routes, with and without a param in the tree.

import Bond from "../../bond"
import Testing from "../../testing"

def one(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "one"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/x/:id", &one) |> Bond.get("/x/y/z", &one)
  path = List.repeat("x", 5000).join("/")
  literal = Testing.request(app, "GET", "/#{path}").status
  deep = Testing.request(app, "GET", "/x/y/#{path}").status
  puts("#{literal} #{deep}")
end
