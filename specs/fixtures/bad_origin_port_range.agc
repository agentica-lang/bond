## A program with an allowed origin that has a port out of 1 to 65535: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

def main() -> Void
  app = Bond.app() |> Bond.csrf(["https://admin.example.net:99999"])
  puts("built #{app.before_filters.size}")
end
