## The app the features run. It is like the todo app of `examples/todos.agc` (its body is plain text) with a few
## routes more for the filters and the errors.

import Cookie from "std/cookie"
import EAG from "std/eag"
import HTML from "std/html"
import Bond from "../../bond"

TOKEN = "letmein"

# The secrets of the session app: the first is the one it signs with at first, the second the one after a rotation.
FIRST_SECRET = "first-secret-first-secret-first-secret"
SECOND_SECRET = "second-secret-second-secret-second-sec"

struct Person
  id: Int
  name: String
  email: Optional[String] = none
end

# Needs a field that Person does not have, so the person that the filter assigned is not one of these.
struct Team
  members: List[String]
end

struct Todo
  id: Int
  title: String
end

export type Producers = Channel[Task[Void]]

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

# A comment of the room view below.
struct RoomComment
  author: String
  text: String
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]
end

# The same app with custom handlers for a path with no route and for a failure. The error handler answers by path so
# that one app shows each case: it gives an error for /filter-error and crashes for /boom-again.
export def build_custom(producers: Producers) -> Bond.App
  (
    build(producers)
    |> Bond.get("/boom-again", &boom)
    |> Bond.not_found(&custom_not_found)
    |> Bond.on_error(&custom_error)
  )
end

## A small app with `Bond.csrf`: `GET /balance` is safe, and `/transfer` answers every unsafe method. The app with
## `allowed` also lets the origin `https://admin.example.net` through.
export def build_csrf(allowed: Bool) -> Bond.App
  origins: List[String] = []
  if allowed
    origins = ["https://admin.example.net"]
  end

  (
    Bond.app()
    |> Bond.csrf(origins)
    |> Bond.get("/balance", &balance)
    |> Bond.post("/transfer", &transfer)
    |> Bond.put("/transfer", &transfer)
    |> Bond.patch("/transfer", &transfer)
    |> Bond.delete("/transfer", &transfer)
  )
end

## The options of the session app. `rotated` is the app after the secret changed: it signs with the second secret and
## still reads what the first signed.
export def session_options(rotated: Bool) -> Bond.SessionOptions
  return Bond.SessionOptions(secret: SECOND_SECRET, old_secrets: [FIRST_SECRET]) if rotated

  Bond.SessionOptions(secret: FIRST_SECRET)
end

## The options of a visitor whose session ended a minute ago: `Testing.session_cookie` signs it with the first secret.
export def expired_options() -> Bond.SessionOptions = Bond.SessionOptions(secret: FIRST_SECRET, max_age: -60)

## A small app with the signed cookie sessions (`Bond.sessions`) and a few routes that read and change the session.
export def build_sessions(rotated: Bool) -> Bond.App
  (
    Bond.app()
    |> Bond.sessions(session_options(rotated))
    |> Bond.get("/me", &me)
    |> Bond.get("/login/:name", &login_as)
    |> Bond.get("/forget", &forget)
    |> Bond.get("/logout", &sign_out)
    |> Bond.get("/visits", &visits)
    |> Bond.get("/peek", &me)
    |> Bond.get("/blob", &blob)
  )
end

## A small app whose `before` filter assigns the person of the `x-user` header (a sign-in check that looked them up
## once) and whose handlers read it back with `Bond.assigned`.
export def build_assigns() -> Bond.App
  (
    Bond.app()
    |> Bond.before(&load_person)
    |> Bond.before(&mark_person)
    |> Bond.get("/me", &who_is_signed_in)
    |> Bond.get("/as-team", &as_team)
    |> Bond.get("/nobody", &nobody)
  )
end

export def build(producers: Producers) -> Bond.App = build_in("specs/fixtures/public", producers)

## The folder of the static files is relative to the working directory: `agentica test` runs the app in process from the
## project folder, while the program of a socket scenario runs from the folder of its feature (`specs/`).
##
## `producers` is where the routes of the streams put the task of each producer they start, so that a step can wait
## for them to end (a BDD handler must not return with a task pending). A program that serves forever gives a channel
## nobody reads: a send that cannot be made is dropped.
export def build_in(public: String, producers: Producers) -> Bond.App
  store = Store(todos: ATS.new(), next_id: ATS.new())
  stopped: ATS[String, Bool] = ATS.new()
  (
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
    |> Bond.get("/client", &client_address)
    |> Bond.get("/greet", &greet)
    |> Bond.get("/template", &eag_page)
    |> Bond.get("/room", &room_view)
    |> Bond.get("/", &root_page)
    |> Bond.post("/only-post", &hello)
    |> Bond.get("/a/lit/:y/z", &deep_z)
    |> Bond.get("/a/:x/c", &deep_c)
    |> Bond.get("/things/:id", &thing)
    |> Bond.post("/things/:id", &update_thing)
    |> Bond.get("/things/new", &new_thing)
    |> Bond.get("/docs/:page/edit", &docs_edit)
    |> Bond.get("/docs/guide/intro", &docs_intro)
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
    |> Bond.get("/assets/override.txt", &hello)
    |> Bond.get("/download") do |conn| Bond.send_file(conn, "#{public}/hello.txt", some("report.txt")) end
    |> Bond.get("/download-unicode") do |conn| Bond.send_file(conn, "#{public}/hello.txt", some("café \"x\".txt")) end
    |> Bond.get("/download-hostile") do |conn| Bond.send_file(conn, "#{public}/hello.txt", some(hostile())) end
    |> Bond.get("/download-nameless") do |conn| Bond.send_file(conn, "#{public}/hello.txt", some("")) end
    |> Bond.get("/download-not-found") do |conn| not_found_file(public, conn) end
    |> Bond.get("/download-plain") do |conn| Bond.send_file(conn, "#{public}/hello.txt") end
    |> Bond.get("/download-png") do |conn| Bond.send_file(conn, "#{public}/pixel.png") end
    |> Bond.get("/download-empty") do |conn| Bond.send_file(conn, "#{public}/empty.txt") end
    |> Bond.get("/download-fresh") do |conn| Bond.send_file(conn, "#{public}/hello.txt", none, some(0)) end
    |> Bond.get("/download-kept") do |conn| Bond.send_file(conn, "#{public}/hello.txt", none, some(600)) end
    |> Bond.get("/download-public") do |conn| Bond.send_file(conn, "#{public}/hello.txt", none, some(600), true) end
    |> Bond.get("/download-age-low") do |conn| Bond.send_file(conn, "#{public}/hello.txt", none, some(-1)) end
    |> Bond.get("/download-piece-low") do |conn|
      Bond.send_file(conn, "#{public}/hello.txt", none, none, false, 100)
    end
    |> Bond.get("/download-replaced") do |conn| replaced_file(public, conn) end
    |> Bond.get("/download-own-cache") do |conn| own_cache_file(public, conn) end
    |> Bond.get("/download-missing") do |conn| Bond.send_file(conn, "#{public}/missing.txt") end
    |> Bond.get("/download-folder") do |conn| Bond.send_file(conn, "#{public}/sub") end
    |> Bond.static("/assets", public)
    |> Bond.static("/small", public, 10)
    |> Bond.static("/cached", public, 1_073_741_824, 3600)
    |> Bond.static("/versioned", public, 1_073_741_824, 0, true)
    |> Bond.get("/raw-cookie", &raw_cookie)
    |> Bond.get("/require-sid", &require_sid)
    |> Bond.get("/set-cookie", &set_from_query)
    |> Bond.get("/track/ok", &hello)
    |> Bond.get("/track/fail", &boom)
    |> Bond.get("/params", &query_fields)
    |> Bond.post("/form-params", &form_fields)
    |> Bond.post("/signup", &signup)
    |> Bond.post("/body-text", &body_text)
    |> Bond.post("/body-echo", &body_echo)
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
    |> Bond.get("/header-newline", &header_newline)
    |> Bond.get("/header-value", &header_value)
    |> Bond.get("/header-wide", &header_wide)
    |> Bond.get("/header-latin1", &header_latin1)
    |> Bond.get("/events") do |conn| events(producers, conn) end
    |> Bond.get("/events-304") do |conn| events_not_modified(producers, conn) end
    |> Bond.get("/events-bad-header") do |conn| events_bad_header(producers, conn) end
    |> Bond.get("/events-binary", &events_binary)
    |> Bond.get("/events-replaced") do |conn| events_replaced(producers, conn) end
    |> Bond.get("/endless") do |conn| endless(producers, stopped, conn) end
    |> Bond.get("/endless-stopped") do |conn| endless_stopped(stopped, conn) end
  )
end

def fail_on_request(conn: Bond.Conn) -> Result[Bond.Conn]
  return error("a filter failed") if conn.path == "/filter-error"

  ok(conn)
end

# A before filter that redirects: the redirect halts, so no route is needed for /legacy.
def redirect_legacy(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/hello")) if conn.path == "/legacy"

  ok(conn)
end

def require_token(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/private" and Bond.request_header(conn, "X-Token").unwrap_or("") != TOKEN
    return ok(Bond.halt(conn, 401, "unauthorized"))
  end

  ok(conn)
end

# Each of these adds its letter to x-trace, so the header shows the order the filters ran in.
def trace_a(conn: Bond.Conn) -> Result[Bond.Conn] = ok(trace(conn, "a"))

def trace_b(conn: Bond.Conn) -> Result[Bond.Conn] = ok(trace(conn, "b"))

def trace_c(conn: Bond.Conn) -> Result[Bond.Conn] = ok(trace(conn, "c"))

def trace(conn: Bond.Conn, letter: String) -> Bond.Conn
  seen = conn.response_headers.select do |header| header.name == "x-trace" end
  before = seen.map do |header| header.value end.join("")
  Bond.header(conn, "x-trace", before + letter)
end

def sign(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.header(conn, "x-powered-by", "bond"))

# A name that tries to end the header and start another (CR LF), with a NUL, a quote and a backslash.
def hostile() -> String = "a\r\nSet-Cookie: x=1#{String.from_code(0)}\"b\\.txt"

# A page of a file with another status: `Bond.status` comes after `send_file`, which sets 200.
def not_found_file(public: String, conn: Bond.Conn) -> Result[Bond.Conn]
  sent = try Bond.send_file(conn, "#{public}/hello.txt")
  ok(Bond.status(sent, 404))
end

# A filter that changes the body of a file answer: the length that `send_file` noted is no longer the size of the body.
def replaced_file(public: String, conn: Bond.Conn) -> Result[Bond.Conn]
  sent = try Bond.send_file(conn, "#{public}/hello.txt")
  ok(sent.with(response_body: "short".bytes))
end

# A route that sets its own `Cache-Control` before `send_file`, which keeps it.
def own_cache_file(public: String, conn: Bond.Conn) -> Result[Bond.Conn]
  Bond.send_file(Bond.header(conn, "cache-control", "max-age=5"), "#{public}/hello.txt")
end

def hello(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "hello"))

def client_address(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, conn.remote_addr))

# The pattern of the guide: a value of the client is escaped before it goes into HTML.
def greet(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  ok(Bond.html(conn, 200, "<p>Hello, #{HTML.escape(name)}</p>"))
end

# An EAG template that escapes with `Bond.escape`: `<%= %>` is escaped in the text and in the attribute (quoted with
# `'` here, so the feature can write the body), and `<%== %>` is the raw form, here for a markup of the app.
def eag_page(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  note = "<em>trusted</em>"
  body = <<~EAG
    <%@ escape &Bond.escape %>
    <p title='<%= name %>'>Hello, <%= name %> <%== note %></p>
  EAG
  ok(Bond.html(conn, 200, body.strip))
end

# The views of the guide: functions that return a String; the layout takes the inner HTML.
def view_comment(comment: RoomComment) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <li class='comment'><b><%= comment.author %></b>: <%= comment.text %></li>
  EAG
end

def view_room(name: String, comments: List[RoomComment]) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <h1><%= name %></h1>
    <ul>
    <% for comment in comments %>
    <%== view_comment(comment) -%>
    <% end %>
    </ul>
  EAG
end

def view_layout(title: String, inner: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <title><%= title %></title>
    <main>
    <%== inner -%>
    </main>
  EAG
end

def room_view(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  comments = [RoomComment(author: "Ana", text: "hello"), RoomComment(author: name, text: name)]
  ok(Bond.html(conn, 200, view_layout(name, view_room(name, comments))))
end

# The routes of the precedence scenarios. `/things/:id` is added before `/things/new` on purpose.
def thing(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "thing #{try Bond.param(conn, "id")}"))

def update_thing(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.text(conn, 200, "updated #{try Bond.param(conn, "id")}"))
end

def new_thing(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "a new thing"))

def docs_intro(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "the intro"))

def docs_edit(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "edit #{try Bond.param(conn, "page")}"))

def root_page(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "the root"))

def deep_z(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "z"))

# Reports the params it sees, to show that a branch the walk left leaves none behind.
def deep_c(conn: Bond.Conn) -> Result[Bond.Conn]
  x = Bond.param(conn, "x").unwrap_or("absent")
  y = Bond.param(conn, "y").unwrap_or("absent")
  ok(Bond.text(conn, 200, "x=#{x} y=#{y}"))
end

def show_post(conn: Bond.Conn) -> Result[Bond.Conn]
  user = try Bond.param(conn, "user_id")
  post = try Bond.param(conn, "post_id")
  ok(Bond.text(conn, 200, "user #{user}, post #{post}"))
end

def list_todos(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.from(store.todos.to_map.values)))
end

def create_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  title = try Bond.body_text(conn)
  return Bond.bad_request("title is empty") if title.empty?

  todo = Todo(id: store.next_id.add("todo", 1), title: title)
  store.todos.put(todo.id, todo)
  ok(Bond.json_as(conn, 201, Todo.codec, todo))
end

# The text of the body, or the 400 of `body_text`.
def body_text(conn: Bond.Conn) -> Result[Bond.Conn]
  text = try Bond.body_text(conn)
  ok(Bond.text(conn, 200, "text #{text}"))
end

# The bytes of the body, sent back as they came.
def body_echo(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.bytes(conn, 200, conn.body))

def latest(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "the latest todo"))

def show_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  case store.todos.get(id)
    ok(todo) -> ok(Bond.json_as(conn, 200, Todo.codec, todo))
    error(_) -> ok(Bond.halt(conn, 404, "not found"))
  end
end

def private_page(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "secret page"))

def boom(conn: Bond.Conn) -> Result[Bond.Conn] = error("secret details")

def crash(conn: Bond.Conn) -> Result[Bond.Conn]
  nothing: List[String] = []
  ok(Bond.text(conn, 200, nothing[3]))
end

def not_modified(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 304, "not sent"))

def status_99(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 99, "too low"))

def content_length(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.header(Bond.text(conn, 200, "x"), "Content-Length", "1"))
end

def transfer_encoding(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.header(Bond.text(conn, 200, "x"), "transfer-encoding", "chunked"))
end

def page(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.html(conn, 200, "<p>hi</p>"))

def accepted(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.status(conn, 202))

# The text is answered first so that the scenario sees the redirect drop its content type and body.
def redirect_default(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(Bond.text(conn, 200, "moved"), "/hello"))

def location_non_ascii(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(conn, "/café"))

def location_newline(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(conn, "/hello\r\nx-evil: 1"))

def header_bad_name(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.header(conn, "x bad", "1"))

def header_newline(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.header(conn, "x-note", "a\r\nx-evil: 1"))

# The value comes from the query, to try the bytes that the server refuses.
def header_value(conn: Bond.Conn) -> Result[Bond.Conn]
  value = try Bond.query(conn, "value")
  ok(Bond.header(Bond.text(conn, 200, "ok"), "x-note", "a#{value}b"))
end

def header_wide(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.header(conn, "x-note", "日本"))

# Latin-1 text is a legal value, and so is a tab.
def header_latin1(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.header(Bond.text(conn, 200, "ok"), "x-note", "café\tbar"))
end

# A path that ends in -bad makes the handler fail, to see the error handler answer it.
def custom_not_found(conn: Bond.Conn) -> Result[Bond.Conn]
  return error("the not found handler failed") if conn.path.end_with?("-bad")

  ok(Bond.html(conn, 404, "<h1>No page at #{HTML.escape(conn.path)}</h1>"))
end

def redirect_with(conn: Bond.Conn) -> Result[Bond.Conn]
  code = try Bond.param_int(conn, "status")
  ok(Bond.redirect(conn, "/hello", code))
end

# Shows the message to the test as a header; a real handler would log it and keep it from the client.
def custom_error(conn: Bond.Conn, message: String) -> Result[Bond.Conn]
  return error("the error handler failed") if conn.path == "/filter-error"

  if conn.path == "/boom-again"
    nothing: List[String] = []
    return ok(Bond.html(conn, 500, nothing[0]))
  end

  ok(Bond.header(Bond.html(conn, 500, "Something went wrong"), "x-error", message))
end

# A JSON body is decoded into a struct; a body that does not fit is a 400.
def create_user(conn: Bond.Conn) -> Result[Bond.Conn]
  user = try Bond.json_body(conn, NewUser.codec)
  ok(Bond.text(conn, 201, "hello #{user.name}, #{user.age}"))
end

def create_account(conn: Bond.Conn) -> Result[Bond.Conn]
  account = try Bond.json_body(conn, Account.codec)
  ok(Bond.text(conn, 201, "zip #{account.address.zip}"))
end

# The query string: a required `q`, an optional `page` and every `tag`.
def search(conn: Bond.Conn) -> Result[Bond.Conn]
  q = try Bond.query(conn, "q")
  page = Bond.query_int(conn, "page").unwrap_or(1)
  found = try Bond.query_all(conn, "tag")
  ok(Bond.text(conn, 200, "q=#{q} page=#{page} tags=#{found.join(",")}"))
end

def items(conn: Bond.Conn) -> Result[Bond.Conn]
  count = try Bond.query_int(conn, "n")
  ok(Bond.text(conn, 200, "#{count} items"))
end

# A form body: `name` and `age` are required.
def signup(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.form(conn, "name")
  age = try Bond.form_int(conn, "age")
  ok(Bond.text(conn, 201, "welcome #{name}, #{age}"))
end

def tags(conn: Bond.Conn) -> Result[Bond.Conn]
  found = try Bond.form_all(conn, "tag")
  ok(Bond.text(conn, 200, "tags=#{found.join(",")}"))
end

# Every name with its values, in the order of the first appearance: `a=1|2;b=x`.
def query_fields(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.query_params(conn)
  ok(Bond.text(conn, 200, describe(fields)))
end

def form_fields(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.form_params(conn)
  ok(Bond.text(conn, 200, describe(fields)))
end

def describe(fields: Map[String, List[String]]) -> String
  fields.keys.map do |name| "#{name}=#{fields[name].join("|")}" end.join(";")
end

# The cookies of the request: `sid` through `cookie`, the others through the map.
def whoami(conn: Bond.Conn) -> Result[Bond.Conn]
  sid = Bond.cookie(conn, "sid").unwrap_or("none")
  theme = Bond.cookies(conn).get("theme", "none")
  ok(Bond.text(conn, 200, "sid=#{sid} theme=#{theme}"))
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
  ok(Bond.text(with_pref, 200, "welcome"))
end

def login_redirect(conn: Bond.Conn) -> Result[Bond.Conn]
  with_sid = try Bond.set_cookie(conn, "sid", "abc123")
  ok(Bond.redirect(with_sid, "/whoami"))
end

def logout(conn: Bond.Conn) -> Result[Bond.Conn]
  gone = try Bond.delete_cookie(conn, "sid")
  ok(Bond.text(gone, 200, "bye"))
end

def logout_host(conn: Bond.Conn) -> Result[Bond.Conn]
  gone = try Bond.delete_cookie(conn, "__Host-id")
  ok(Bond.text(gone, 200, "bye"))
end

def bad_cookie(conn: Bond.Conn) -> Result[Bond.Conn]
  bad = try Bond.set_cookie(conn, "sid", "has a space")
  ok(Bond.text(bad, 200, "not reached"))
end

# `header` with Set-Cookie adds to the cookies set before it and does not replace them.
def raw_cookie(conn: Bond.Conn) -> Result[Bond.Conn]
  first = try Bond.set_cookie(conn, "a", "1")
  second = try Bond.set_cookie(first, "b", "2")
  ok(Bond.header(second, "Set-Cookie", "raw=1"))
end

# `try` on a cookie that is not there is a 500, unlike `try` on a query value that is not there.
def require_sid(conn: Bond.Conn) -> Result[Bond.Conn]
  sid = try Bond.cookie(conn, "sid")
  ok(Bond.text(conn, 200, "sid=#{sid}"))
end

# The name and the value come from the query, to try the ones that std/cookie refuses.
def set_from_query(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  value = try Bond.query(conn, "value")
  cookie = try Bond.set_cookie(conn, name, value)
  ok(Bond.text(cookie, 200, "set"))
end

# A before filter that sets a cookie for the paths under /track.
def track_visit(conn: Bond.Conn) -> Result[Bond.Conn]
  return Bond.set_cookie(conn, "visit", "1") if conn.path.start_with?("/track")

  ok(conn)
end

# Hands the task of a producer to whoever waits for it. A full or unread channel drops it.
def keep(producers: Producers, task: Task[Void]) -> Void
  _ = producers.send(task, 1)
end

# A task sends the events and closes the channel, as the guide says a producer must.
def produce(events: Channel[Bytes]) -> Void
  for event in [Bond.sse_event("one"), Bond.sse_event("two\nlines", "note")]
    break if not events.send(event, 5000).ok?
  end

  events.close
end

def events(producers: Producers, conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  keep(producers, Task.spawn(&produce, channel))
  ok(Bond.sse(conn, channel))
end

# A 304 has no body, so the stream is dropped and its channel closed.
def events_not_modified(producers: Producers, conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  keep(producers, Task.spawn(&produce, channel))
  ok(Bond.stream(conn, 304, channel))
end

# A response the server refuses is a plain 500, and the channel of its stream is closed.
def events_bad_header(producers: Producers, conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  keep(producers, Task.spawn(&produce, channel))
  ok(Bond.header(Bond.sse(conn, channel), "content-length", "5"))
end

# The pieces are not UTF-8 text: the body is their bytes.
def events_binary(conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  channel.send(Bytes.from_list([255, 216, 0]).unwrap!, 5000).unwrap!
  channel.close
  ok(Bond.stream(conn, 200, channel))
end

# A body helper after a stream replaces it and closes its channel.
def events_replaced(producers: Producers, conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  keep(producers, Task.spawn(&produce, channel))
  ok(Bond.halt(Bond.sse(conn, channel), 403, "forbidden"))
end

# A producer that never ends by itself: it stops only when its send fails, and says so in `stopped`.
def tick(events: Channel[Bytes], stopped: ATS[String, Bool]) -> Void
  while events.send(Bond.sse_event("tick"), 5000).ok?
    Task.sleep(20)
  end

  stopped.put("endless", true)
  events.close
end

def endless(producers: Producers, stopped: ATS[String, Bool], conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(2)
  keep(producers, Task.spawn() do tick(channel, stopped) end)
  ok(Bond.sse(conn, channel))
end

# Waits (2 s at most) for the producer of /endless to see its channel closed.
def endless_stopped(stopped: ATS[String, Bool], conn: Bond.Conn) -> Result[Bond.Conn]
  for _ in 1..40
    return ok(Bond.text(conn, 200, "stopped")) if stopped.get("endless").ok?

    Task.sleep(50)
  end

  ok(Bond.text(conn, 200, "running"))
end

def me(conn: Bond.Conn) -> Result[Bond.Conn]
  user = Bond.get_session(conn, "user").unwrap_or("nobody")
  ok(Bond.text(conn, 200, "user=#{user} values=#{Bond.session(conn).size}"))
end

def login_as(conn: Bond.Conn) -> Result[Bond.Conn]
  signed_in = Bond.set_session(Bond.clear_session(conn), "user", try Bond.param(conn, "name"))
  ok(Bond.text(signed_in, 200, "welcome"))
end

def forget(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(Bond.delete_session(conn, "user"), 200, "forgotten"))

def sign_out(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(Bond.clear_session(conn), 200, "bye"))

# A number is kept as text in the session.
def visits(conn: Bond.Conn) -> Result[Bond.Conn]
  count = Bond.get_session(conn, "visits").unwrap_or("0").to_i!
  counted = Bond.set_session(conn, "visits", (count + 1).to_s)
  ok(Bond.text(counted, 200, "visits=#{count + 1}"))
end

# A session too big for a cookie.
def blob(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.text(Bond.set_session(conn, "blob", List.repeat("x", 5000).join("")), 200, "stored"))
end

def balance(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "balance 10"))

def transfer(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "transferred"))

def load_person(conn: Bond.Conn) -> Result[Bond.Conn]
  case Bond.request_header(conn, "x-user")
    ok(name) -> ok(Bond.assign(conn, "person", Person(id: 7, name: name, email: some("#{name}@example.com"))))
    error(_) -> ok(conn)
  end
end

# A second filter sees what the first one assigned.
def mark_person(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(conn) if not Bond.assigned?(conn, "person")

  person = try Bond.assigned(conn, "person", Person.codec)
  ok(Bond.header(conn, "x-seen", person.name))
end

def who_is_signed_in(conn: Bond.Conn) -> Result[Bond.Conn]
  person = try Bond.assigned(conn, "person", Person.codec)
  ok(Bond.text(conn, 200, "#{person.id} #{person.name} #{person.email.unwrap_or("-")}"))
end

def as_team(conn: Bond.Conn) -> Result[Bond.Conn]
  refused = not Bond.assigned(conn, "person", Team.codec).ok?
  ok(Bond.text(conn, 200, "refused=#{refused} assigned=#{Bond.assigned?(conn, "person")}"))
end

def nobody(conn: Bond.Conn) -> Result[Bond.Conn]
  refused = not Bond.assigned(conn, "nobody", Person.codec).ok?
  ok(Bond.text(conn, 200, "refused=#{refused} assigned=#{Bond.assigned?(conn, "nobody")}"))
end
