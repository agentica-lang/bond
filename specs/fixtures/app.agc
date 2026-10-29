## The app the features run. It is like the todo app of `examples/todos.agc` (its body is plain text) with a few
## routes more for the filters and the errors.

import Cookie from "std/cookie"
import Bond from "../../bond"

TOKEN = "letmein"

struct Todo
  id: Int
  title: String
end

struct NewUser
  name: String
  age: Int
end

struct Address
  zip: String
end

struct Account
  address: Address
  scores: Map[String, Int]
  tags: List[String]
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]
end

# The same app with custom handlers for a path with no route and for a failure. The error handler answers by path so
# that one app shows each case: it gives an error for /filter-error and crashes for /boom-again.
export def build_custom() -> Bond.App
  return (
    build()
    |> Bond.get("/boom-again", &boom)
    |> Bond.not_found(&custom_not_found)
    |> Bond.on_error(&custom_error)
  )
end

export def build() -> Bond.App
  store = Store(todos: ATS.new(), next_id: ATS.new())
  return (
    Bond.app()
    |> Bond.before(&fail_on_request)
    |> Bond.before(&track_visit)
    |> Bond.before(&redirect_legacy)
    |> Bond.before(&require_token)
    |> Bond.before(&trace_a)
    |> Bond.before(&trace_b)
    |> Bond.after(&trace_c)
    |> Bond.after(&sign)
    |> Bond.get("/hello", &hello)
    |> Bond.get("/users/:user_id/posts/:post_id", &show_post)
    |> Bond.get("/todos") do |conn| list_todos(store, conn) end
    |> Bond.post("/todos") do |conn| create_todo(store, conn) end
    |> Bond.get("/todos/latest", &latest)
    |> Bond.get("/todos/:id") do |conn| show_todo(store, conn) end
    |> Bond.get("/private", &private_page)
    |> Bond.get("/boom", &boom)
    |> Bond.get("/crash", &crash)
    |> Bond.get("/not-modified", &not_modified)
    |> Bond.get("/status-99", &status_99)
    |> Bond.get("/content-length", &content_length)
    |> Bond.get("/transfer-encoding", &transfer_encoding)
    |> Bond.get("/café", &hello)
    |> Bond.get("/search", &search)
    |> Bond.get("/items", &items)
    |> Bond.get("/whoami", &whoami)
    |> Bond.get("/login", &login)
    |> Bond.get("/login-redirect", &login_redirect)
    |> Bond.get("/logout", &logout)
    |> Bond.get("/logout-host", &logout_host)
    |> Bond.get("/bad-cookie", &bad_cookie)
    |> Bond.get("/raw-cookie", &raw_cookie)
    |> Bond.get("/require-sid", &require_sid)
    |> Bond.get("/set-cookie", &set_from_query)
    |> Bond.get("/track/ok", &hello)
    |> Bond.get("/track/fail", &boom)
    |> Bond.get("/params", &query_fields)
    |> Bond.post("/form-params", &form_fields)
    |> Bond.post("/signup", &signup)
    |> Bond.post("/tags", &tags)
    |> Bond.post("/users", &create_user)
    |> Bond.post("/accounts", &create_account)
    |> Bond.get("/page", &page)
    |> Bond.get("/accepted", &accepted)
    |> Bond.get("/redirect", &redirect_default)
    |> Bond.get("/redirect/:status", &redirect_with)
    |> Bond.get("/location-non-ascii", &location_non_ascii)
    |> Bond.get("/location-newline", &location_newline)
    |> Bond.get("/header-bad-name", &header_bad_name)
  )
end

def fail_on_request(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/filter-error"
    return error("a filter failed")
  end

  return ok(conn)
end

# A before filter that redirects: the redirect halts, so no route is needed for /legacy.
def redirect_legacy(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/legacy"
    return ok(Bond.redirect(conn, "/hello"))
  end

  return ok(conn)
end

def require_token(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/private" and Bond.request_header(conn, "X-Token").unwrap_or("") != TOKEN
    return ok(Bond.halt(conn, 401, "unauthorized"))
  end

  return ok(conn)
end

# Each of these adds its letter to x-trace, so the header shows the order the filters ran in.
def trace_a(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(trace(conn, "a"))
end

def trace_b(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(trace(conn, "b"))
end

def trace_c(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(trace(conn, "c"))
end

def trace(conn: Bond.Conn, letter: String) -> Bond.Conn
  seen = conn.response_headers.select do |header| header.name == "x-trace" end
  before = seen.map do |header| header.value end.join("")
  return Bond.header(conn, "x-trace", before + letter)
end

def sign(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.header(conn, "x-powered-by", "bond"))
end

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def show_post(conn: Bond.Conn) -> Result[Bond.Conn]
  user = try Bond.param(conn, "user_id")
  post = try Bond.param(conn, "post_id")
  return ok(Bond.text(conn, 200, "user #{user}, post #{post}"))
end

def list_todos(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.json(conn, 200, JSON.from(store.todos.to_map.values)))
end

def create_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.body.empty?
    return Bond.bad_request("title is empty")
  end

  todo = Todo(id: store.next_id.add("todo", 1), title: conn.body)
  store.todos.put(todo.id, todo)
  return ok(Bond.json(conn, 201, JSON.from(todo)))
end

def latest(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "the latest todo"))
end

def show_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  case store.todos.get(id)
    ok(todo) -> return ok(Bond.json(conn, 200, JSON.from(todo)))
    error(_) -> return ok(Bond.halt(conn, 404, "not found"))
  end
end

def private_page(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "secret page"))
end

def boom(conn: Bond.Conn) -> Result[Bond.Conn]
  return error("secret details")
end

def crash(conn: Bond.Conn) -> Result[Bond.Conn]
  nothing: List[String] = []
  return ok(Bond.text(conn, 200, nothing[3]))
end

def not_modified(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 304, "not sent"))
end

def status_99(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 99, "too low"))
end

def content_length(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.header(Bond.text(conn, 200, "x"), "Content-Length", "1"))
end

def transfer_encoding(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.header(Bond.text(conn, 200, "x"), "transfer-encoding", "chunked"))
end

def page(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 200, "<p>hi</p>"))
end

def accepted(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.status(conn, 202))
end

# The text is answered first so that the scenario sees the redirect drop its content type and body.
def redirect_default(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(Bond.text(conn, 200, "moved"), "/hello"))
end

def location_non_ascii(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/café"))
end

def location_newline(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/hello\r\nx-evil: 1"))
end

def header_bad_name(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.header(conn, "x bad", "1"))
end

# A path that ends in -bad makes the handler fail, to see the error handler answer it.
def custom_not_found(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path.end_with?("-bad")
    return error("the not found handler failed")
  end

  return ok(Bond.html(conn, 404, "<h1>No page at #{conn.path}</h1>"))
end

def redirect_with(conn: Bond.Conn) -> Result[Bond.Conn]
  code = try Bond.param_int(conn, "status")
  return ok(Bond.redirect(conn, "/hello", code))
end

# Shows the message to the test as a header; a real handler would log it and keep it from the client.
def custom_error(conn: Bond.Conn, message: String) -> Result[Bond.Conn]
  if conn.path == "/filter-error"
    return error("the error handler failed")
  end

  if conn.path == "/boom-again"
    nothing: List[String] = []
    return ok(Bond.html(conn, 500, nothing[0]))
  end

  return ok(Bond.header(Bond.html(conn, 500, "Something went wrong"), "x-error", message))
end

# A JSON body is decoded into a struct; a body that does not fit is a 400.
def create_user(conn: Bond.Conn) -> Result[Bond.Conn]
  user = try Bond.json_body(conn, JSON.codec(NewUser))
  return ok(Bond.text(conn, 201, "hello #{user.name}, #{user.age}"))
end

def create_account(conn: Bond.Conn) -> Result[Bond.Conn]
  account = try Bond.json_body(conn, JSON.codec(Account))
  return ok(Bond.text(conn, 201, "zip #{account.address.zip}"))
end

# The query string: a required `q`, an optional `page` and every `tag`.
def search(conn: Bond.Conn) -> Result[Bond.Conn]
  q = try Bond.query(conn, "q")
  page = Bond.query_int(conn, "page").unwrap_or(1)
  found = try Bond.query_all(conn, "tag")
  return ok(Bond.text(conn, 200, "q=#{q} page=#{page} tags=#{found.join(",")}"))
end

def items(conn: Bond.Conn) -> Result[Bond.Conn]
  count = try Bond.query_int(conn, "n")
  return ok(Bond.text(conn, 200, "#{count} items"))
end

# A form body: `name` and `age` are required.
def signup(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.form(conn, "name")
  age = try Bond.form_int(conn, "age")
  return ok(Bond.text(conn, 201, "welcome #{name}, #{age}"))
end

def tags(conn: Bond.Conn) -> Result[Bond.Conn]
  found = try Bond.form_all(conn, "tag")
  return ok(Bond.text(conn, 200, "tags=#{found.join(",")}"))
end

# Every name with its values, in the order of the first appearance: `a=1|2;b=x`.
def query_fields(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.query_params(conn)
  return ok(Bond.text(conn, 200, describe(fields)))
end

def form_fields(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.form_params(conn)
  return ok(Bond.text(conn, 200, describe(fields)))
end

def describe(fields: Map[String, List[String]]) -> String
  return fields.keys.map do |name| "#{name}=#{fields[name].join("|")}" end.join(";")
end

# The cookies of the request: `sid` through `cookie`, the others through the map.
def whoami(conn: Bond.Conn) -> Result[Bond.Conn]
  sid = Bond.cookie(conn, "sid").unwrap_or("none")
  theme = Bond.cookies(conn).get("theme", "none")
  return ok(Bond.text(conn, 200, "sid=#{sid} theme=#{theme}"))
end

# `set_cookie` with the defaults of Bond, then every attribute through `set_cookie_with`.
def login(conn: Bond.Conn) -> Result[Bond.Conn]
  with_sid = try Bond.set_cookie(conn, "sid", "abc123")
  theme = Cookie.Cookie(
    name: "theme",
    value: "dark",
    path: "/app",
    domain: "example.com",
    max_age: 3600,
    secure: true,
    same_site: "None",
  )
  pref = Cookie.Cookie(name: "pref", value: "wide", expires: "Wed, 21 Oct 2015 07:28:00 GMT", http_only: true)
  with_theme = try Bond.set_cookie_with(with_sid, theme)
  with_pref = try Bond.set_cookie_with(with_theme, pref)
  return ok(Bond.text(with_pref, 200, "welcome"))
end

def login_redirect(conn: Bond.Conn) -> Result[Bond.Conn]
  with_sid = try Bond.set_cookie(conn, "sid", "abc123")
  return ok(Bond.redirect(with_sid, "/whoami"))
end

def logout(conn: Bond.Conn) -> Result[Bond.Conn]
  gone = try Bond.delete_cookie(conn, "sid")
  return ok(Bond.text(gone, 200, "bye"))
end

def logout_host(conn: Bond.Conn) -> Result[Bond.Conn]
  gone = try Bond.delete_cookie(conn, "__Host-id")
  return ok(Bond.text(gone, 200, "bye"))
end

def bad_cookie(conn: Bond.Conn) -> Result[Bond.Conn]
  bad = try Bond.set_cookie(conn, "sid", "has a space")
  return ok(Bond.text(bad, 200, "not reached"))
end

# `header` with Set-Cookie adds to the cookies set before it and does not replace them.
def raw_cookie(conn: Bond.Conn) -> Result[Bond.Conn]
  first = try Bond.set_cookie(conn, "a", "1")
  second = try Bond.set_cookie(first, "b", "2")
  return ok(Bond.header(second, "Set-Cookie", "raw=1"))
end

# `try` on a cookie that is not there is a 500, unlike `try` on a query value that is not there.
def require_sid(conn: Bond.Conn) -> Result[Bond.Conn]
  sid = try Bond.cookie(conn, "sid")
  return ok(Bond.text(conn, 200, "sid=#{sid}"))
end

# The name and the value come from the query, to try the ones that std/cookie refuses.
def set_from_query(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  value = try Bond.query(conn, "value")
  cookie = try Bond.set_cookie(conn, name, value)
  return ok(Bond.text(cookie, 200, "set"))
end

# A before filter that sets a cookie for the paths under /track.
def track_visit(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path.start_with?("/track")
    return Bond.set_cookie(conn, "visit", "1")
  end

  return ok(conn)
end
