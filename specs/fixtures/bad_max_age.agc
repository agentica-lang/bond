## A program with a negative `max_age` for a static folder: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.static("/assets", "fixtures/public", 1_048_576, -1)
  puts("built #{app.statics.size}")
end
