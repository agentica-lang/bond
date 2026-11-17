import HTTP from "std/http"
import Bond from "../bond"
import Testing from "../testing"
import Conns from "../src/conn"

private

SECRET = "a secret of at least thirty-two bytes, for the test"

def handler(f: Bond.Handler) -> Bond.Handler = f

def request(headers: List[HTTP.Header]) -> Conns.Conn
  Conns.from_request(
    HTTP.Request(method: "GET", target: "/", path: "/", headers: headers, body: "".bytes, remote_addr: "127.0.0.1"),
  )
end

def main() -> Void
  Test.run([
    Test.test("a request header is found by a name in any case, and the first one wins") do
      conn = request([
        HTTP.Header(name: "host", value: "a"),
        HTTP.Header(name: "x-token", value: "1"),
        HTTP.Header(name: "x-token", value: "2"),
      ])

      try Test.eq(Conns.request_header(conn, "X-Token").unwrap_or(""), "1")
      try Test.eq(Conns.request_header(conn, "x-token").unwrap_or(""), "1")
      mixed = request([HTTP.Header(name: "X-Token", value: "m")])
      try Test.eq(Conns.request_header(mixed, "x-token").unwrap_or(""), "m")
      Test.assert(not Conns.request_header(conn, "x-token-2").ok?, "a longer name is another header")
    end,
    Test.test("Bond.handle reads the session and the headers of a request whose names are not in lowercase") do
      options = Bond.SessionOptions(secret: SECRET)
      shown = handler do |conn|
        user = Bond.get_session(conn, "user").unwrap_or("")
        token = Bond.request_header(conn, "x-token").unwrap_or("")
        ok(Bond.text(conn, 200, "#{user} #{token}"))
      end

      app = (
        Bond.app()
        |> Bond.sessions(options)
        |> Bond.get("/", shown)
      )

      cookie = try Testing.session_cookie(options, {"user": "ana"})
      headers = [HTTP.Header(name: "Cookie", value: cookie), HTTP.Header(name: "X-Token", value: "t")]
      response = Bond.handle(
        app,
        HTTP.Request(
          method: "GET",
          target: "/",
          path: "/",
          headers: headers,
          body: "".bytes,
          remote_addr: "127.0.0.1",
        ),
      )

      Test.eq(Testing.text(response).unwrap_or(""), "ana t")
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
    Test.test(
      "set_headers replaces the headers of the same name in any case, keeps the others, and appends in order",
    ) do
      fields = [HTTP.Header(name: "etag", value: "n"), HTTP.Header(name: "vary", value: "v")]
      empty = Conns.set_headers(request([]), fields)
      try Test.eq(empty.response_headers.map do |field| field.value end, ["n", "v"])
      conn = Conns.add_header(Conns.add_header(request([]), "ETag", "old"), "x-keep", "k")
      set = Conns.set_headers(conn, fields)
      try Test.eq(set.response_headers.map do |field| field.name end, ["x-keep", "etag", "vary"])
      Test.eq(set.response_headers.map do |field| field.value end, ["k", "n", "v"])
    end,
    Test.test("set_headers keeps a Set-Cookie and drops every header of a name it sets") do
      cookie = Conns.add_header(request([]), "Set-Cookie", "a=1")
      conn = Conns.add_header(Conns.add_header(cookie, "ETag", "1"), "etag", "2")
      set = Conns.set_headers(conn, [HTTP.Header(name: "etag", value: "n")])
      Test.eq(set.response_headers.map do |field| "#{field.name}=#{field.value}" end, ["Set-Cookie=a=1", "etag=n"])
    end,
  ])
end
