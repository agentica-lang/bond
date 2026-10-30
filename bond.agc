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
import Cookies from "src/cookies"
import Filters from "src/filters"
import Queries from "src/query"
import Servers from "src/server"

export Apps.App
export Apps.app
export Apps.get
export Apps.post
export Apps.put
export Apps.patch
export Apps.delete
export Apps.not_found
export Apps.on_error
export Apps.static
export Apps.before
export Apps.after
export Apps.handle
export Conns.Conn
export Conns.Handler
export Conns.ErrorHandler
export Conns.text
export Conns.json
export Conns.json_as
export Conns.json_body
export Conns.halt
export Conns.html
export Conns.status
export Conns.redirect
export Conns.header
export Conns.request_header
export Conns.bad_request
export Conns.param
export Conns.param_int
export Cookies.cookies
export Cookies.cookie
export Cookies.set_cookie
export Cookies.set_cookie_with
export Cookies.delete_cookie
export Filters.log_request
export Queries.query
export Queries.query_int
export Queries.query_all
export Queries.query_params
export Queries.form_params
export Queries.form
export Queries.form_int
export Queries.form_all
export Servers.start
export Servers.start_with
export Servers.run_with
export Servers.local_port
export Servers.wait
export Servers.stop
export Servers.run
