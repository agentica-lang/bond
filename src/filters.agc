## Filters that Bond provides.

import Conns from "conn"
import {Conn} from "conn"

## A `before` filter that writes `METHOD /path` of each request to stderr.
export def log_request(conn: Conn) -> Result[Conn]
  IO.warn("#{conn.method} #{conn.path}")
  return ok(conn)
end
