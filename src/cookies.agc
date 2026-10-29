## The cookies of a request and of a response, read and written with `std/cookie`.

import C from "std/cookie"
import {Conn} from "conn"

export def cookies(conn: Conn) -> Map[String, String]
  return {}
end

export def cookie(conn: Conn, name: String) -> Result[String]
  return error("not written yet")
end

export def set_cookie(conn: Conn, name: String, value: String) -> Result[Conn]
  return ok(conn)
end

export def set_cookie_with(conn: Conn, cookie: C.Cookie) -> Result[Conn]
  return ok(conn)
end

export def delete_cookie(conn: Conn, name: String, path: String = "/", domain: String = "") -> Result[Conn]
  return ok(conn)
end
