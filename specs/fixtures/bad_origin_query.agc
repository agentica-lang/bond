## A program with an allowed origin that is not only a scheme, a host and a port: building the app stops it, so `puts` is never reached.

import Bond from "../../bond"

private

def main() -> Void
  app = Bond.app() |> Bond.csrf(["https://admin.example.net?x=1"])
  puts("built #{app.before_filters.size}")
end
