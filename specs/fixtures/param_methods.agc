## Another method with another name for the same param: building the app stops the program.

import Bond from "../../bond"

def one(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "one"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/users/:id", &one)
    |> Bond.post("/users/:uid", &one)
  )
  puts("built #{app.before_filters.size}")
end
