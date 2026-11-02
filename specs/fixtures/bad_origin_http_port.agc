## A program with an allowed origin that has the default port of http, which a browser leaves out of the Origin: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.csrf(["http://admin.example.net:80"])
  puts("built #{app.before_filters.size}")
end
