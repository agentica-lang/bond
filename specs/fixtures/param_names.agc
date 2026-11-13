## Two names for the param at the same place: building the app stops the program.

import Bond from "../../bond"

private

def one(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "one"))

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/users/:id", &one)
    |> Bond.get("/users/:name/posts", &one)
  )

  puts("built #{app.before_filters.size}")
end
