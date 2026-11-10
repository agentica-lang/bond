## A trailing slash does not make another route, so this is the same pattern twice.

import Bond from "../../bond"

def one(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "one"))

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/hello", &one)
    |> Bond.get("/hello/", &one)
  )

  puts("built #{app.before_filters.size}")
end
