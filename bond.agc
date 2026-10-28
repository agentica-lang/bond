## Bond: a small web framework in the spirit of Sinatra.
##
## ```ruby
## import Bond from "pkg/bond/bond"
##
## def hello(conn: Bond.Conn) -> Result[Bond.Conn]
##   return ok(Bond.text(conn, 200, "hello"))
## end
##
## def main() -> Void
##   app = Bond.app() |> Bond.get("/hello", &hello)
##   Bond.run(app, "127.0.0.1", 4567).unwrap!
## end
## ```

import Apps from "src/app"
import Conns from "src/conn"
import Filters from "src/filters"
import Servers from "src/server"

export Apps.App
export Apps.app
export Apps.get
export Apps.post
export Apps.put
export Apps.patch
export Apps.delete
export Apps.before
export Apps.after
export Apps.handle
export Conns.Conn
export Conns.Handler
export Conns.text
export Conns.json
export Conns.halt
export Conns.header
export Conns.request_header
export Conns.bad_request
export Conns.param
export Conns.param_int
export Filters.log_request
export Servers.start
export Servers.local_port
export Servers.wait
export Servers.stop
export Servers.run
