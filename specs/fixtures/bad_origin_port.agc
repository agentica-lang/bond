## A program with an allowed origin that has the default port of https, which a browser leaves out of the Origin: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.csrf(["https://admin.example.net:443"])
  puts("built #{app.before_filters.size}")
end
