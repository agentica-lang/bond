## A program that serves a folder that does not exist: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.static("/assets", "no_such_folder")
  puts("built #{app.statics.size}")
end
