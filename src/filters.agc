## Filters that Bond provides.

import {Conn} from "conn"

## A `before` filter that writes `METHOD /path` of each request to stderr.
def log_request(conn: Conn) -> Result[Conn]
  IO.warn("#{conn.method} #{conn.path}")
  ok(conn)
end
