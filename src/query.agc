## The query string and the form body of a request, read with `std/uri`.

import {Conn} from "conn"

export def query(conn: Conn, name: String) -> Result[String]
  return error("not written yet")
end

export def query_int(conn: Conn, name: String) -> Result[Int]
  return error("not written yet")
end

export def query_all(conn: Conn, name: String) -> Result[List[String]]
  return error("not written yet")
end

export def form(conn: Conn, name: String) -> Result[String]
  return error("not written yet")
end

export def form_int(conn: Conn, name: String) -> Result[Int]
  return error("not written yet")
end

export def form_all(conn: Conn, name: String) -> Result[List[String]]
  return error("not written yet")
end
