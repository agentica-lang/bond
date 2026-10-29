## The program of `server.feature`: the app on 127.0.0.1 and a free port. It says the port on its first line.

import Bond from "../../bond"
import Fixture from "app"

def main() -> Void
  server = Bond.start(Fixture.build_in("fixtures/public"), "127.0.0.1", 0).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
