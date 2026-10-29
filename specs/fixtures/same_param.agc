## The same pattern with other methods, and the same param name deeper, build the app.

import Bond from "../../bond"

def one(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "one"))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/users/:id", &one)
    |> Bond.post("/users/:id", &one)
    |> Bond.get("/users/:id/posts", &one)
  )
  puts("built #{app.before_filters.size}")
end
