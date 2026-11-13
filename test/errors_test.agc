import HTTP from "std/http"
import Cookie from "std/cookie"
import Bond from "../bond"
import Testing from "../testing"
import Conns from "../src/conn"

private

def with_kind(conn: Bond.Conn) -> Result[Bond.Conn] = error("db down", kind: "db.constraint", code: 19)

def plain(conn: Bond.Conn) -> Result[Bond.Conn] = error("plain text")

# `set_cookie` refuses the value (a space), and the handler passes the error on with `try`.
def wrapped(conn: Bond.Conn) -> Result[Bond.Conn]
  conn = try Bond.set_cookie(conn, "a", "bad value")
  ok(conn)
end

# The handler of failures gets the message as a String, whatever the kind of the error.
def report(conn: Bond.Conn, message: String) -> Result[Bond.Conn] = ok(Bond.text(conn, 500, "failed: #{message}"))

def app() -> Bond.App
  (
    Bond.app()
    |> Bond.get("/kind", &with_kind)
    |> Bond.get("/plain", &plain)
    |> Bond.get("/wrapped", &wrapped)
    |> Bond.on_error(&report)
  )
end

def body_of(path: String) -> String = String.from_bytes(Testing.request(app(), "GET", path).body).unwrap!

# The kind, the code and the cause of a failed Result, as text, so two errors compare by them and not by message.
def shape[T](result: Result[T]) -> String
  case result
    ok(_) -> "ok"
    error(e) -> "#{e.kind} #{e.code} #{e.cause}"
  end
end

def blank() -> Bond.Conn
  Conns.from_request(
    HTTP.Request(method: "GET", target: "/", path: "/", headers: [], body: "".bytes, remote_addr: "127.0.0.1"),
  )
end

def main() -> Void
  Test.run([
    Test.test("an error with a kind and one with plain text are both a 500 that gives its message to on_error") do
      try Test.eq(Testing.request(app(), "GET", "/kind").status, 500)
      try Test.eq(body_of("/kind"), "failed: db down")
      try Test.eq(Testing.request(app(), "GET", "/plain").status, 500)
      Test.eq(body_of("/plain"), "failed: plain text")
    end,
    Test.test("without on_error the message of an error with a kind stays out of the answer") do
      plain_app = Bond.app() |> Bond.get("/kind", &with_kind)
      response = Testing.request(plain_app, "GET", "/kind")
      try Test.eq(response.status, 500)
      Test.eq(String.from_bytes(response.body).unwrap!, "Internal Server Error")
    end,
    Test.test(
      "set_cookie keeps the kind, the code and the cause of the error of std/cookie, with its message first",
    ) do
      refused = Cookie.set_header(
        Cookie.Cookie(name: "a", value: "bad value", path: "/", http_only: true, same_site: "Lax"),
      )

      wrapped_cookie = Bond.set_cookie(blank(), "a", "bad value")
      try Test.eq(shape(refused), "argument none none")
      try Test.eq(shape(wrapped_cookie), shape(refused))
      Test.eq(wrapped_cookie.message.start_with?("cookie: "), true)
    end,
    Test.test("a wrapped failure of a handler is still a 500 with the message of the wrapper") do
      body = body_of("/wrapped")
      Test.assert(body.start_with?("failed: cookie: "), body)
    end,
  ])
end
