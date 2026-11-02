## A program with an allowed origin that has a scheme that is not http or https: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.csrf(["ftp://admin.example.net"])
  puts("built #{app.before_filters.size}")
end
