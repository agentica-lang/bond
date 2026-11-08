import Conns from "../src/conn"

def request(headers: List[Header]) -> Conns.Conn
  return Conns.from_request(
    HttpRequest(method: "GET", target: "/", path: "/", headers: headers, body: "".bytes, remote_addr: "127.0.0.1"),
  )
end

def main() -> Void
  Test.run([
    Test.test("a request header is found in any case of the name, and the first one wins") do
      conn = request([
        Header(name: "host", value: "a"),
        Header(name: "x-token", value: "1"),
        Header(name: "x-token", value: "2"),
      ])

      try Test.eq(Conns.request_header(conn, "X-Token").unwrap_or(""), "1")
      try Test.eq(Conns.request_header(conn, "x-token").unwrap_or(""), "1")
      mixed = request([Header(name: "X-Token", value: "m")])
      try Test.eq(Conns.request_header(mixed, "x-token").unwrap_or(""), "m")
      Test.assert(not Conns.request_header(conn, "x-token-2").ok?, "a longer name is another header")
    end,
    Test.test("a response header replaces the one of the same name in any case, and keeps the others") do
      conn = request([])
      set = Conns.header(Conns.header(Conns.header(conn, "etag", "a"), "x-keep", "k"), "ETag", "b")
      try Test.eq(set.response_headers.map do |field| field.name end, ["x-keep", "ETag"])
      try Test.eq(set.response_headers.map do |field| field.value end, ["k", "b"])
      stored = Conns.add_header(conn, "ETag", "a")
      replaced = Conns.header(stored, "etag", "b")
      try Test.eq(replaced.response_headers.map do |field| field.value end, ["b"])
      cookies = Conns.header(Conns.header(conn, "Set-Cookie", "a=1"), "set-cookie", "b=2")
      Test.eq(cookies.response_headers.map do |field| field.value end, ["a=1", "b=2"])
    end,
  ])
end
