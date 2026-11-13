## The program of the body limit scenarios of `server.feature`: the app on 127.0.0.1 and a free port, with a body
## limit of 8 bytes and a request timeout of one second. It says the port on its first line.

import HTTP from "std/http"
import Bond from "../../bond"
import Fixture from "app"

private

BODY_LIMIT = 8
# A client that stops sending is cut off after this long, so the scenario of a stalled body ends quickly.
STALL_MS = 1_000

def main() -> Void
  producers: Fixture.Producers = Channel.new(1)
  options = HTTP.ServerOptions(max_body_bytes: BODY_LIMIT, request_timeout_ms: STALL_MS)
  server = Bond.start_with(Fixture.build_in("fixtures/public", producers), "127.0.0.1", 0, options).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
