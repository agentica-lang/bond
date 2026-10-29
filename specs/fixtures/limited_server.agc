## The program of the body limit scenarios of `server.feature`: the app on 127.0.0.1 and a free port, with a body
## limit of 8 bytes. It says the port on its first line.

import HTTP from "std/http"
import Bond from "../../bond"
import Fixture from "app"

BODY_LIMIT = 8

def main() -> Void
  options = HTTP.server_options().with(max_body_bytes: BODY_LIMIT)
  server = Bond.start_with(Fixture.build_in("fixtures/public"), "127.0.0.1", 0, options).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
