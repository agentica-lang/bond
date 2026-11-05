## A program with a piece size below the minimum for a static folder: building the app stops it, so `puts` is never
## reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.static("/assets", "fixtures/public", 1_048_576, 0, false, 0, 100)
  puts("built #{app.statics.size}")
end
