## The app the features run. It is the todo app of `examples/todos.agc` with a few routes more for the filters and
## the errors.

import Bond from "../../bond"

TOKEN = "letmein"

struct Todo
  id: Int
  title: String
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]
end

export def build() -> Bond.App
  store = Store(todos: ATS.new(), next_id: ATS.new())
  return (
    Bond.app()
    |> Bond.before(&fail_on_request)
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
  )
end

def fail_on_request(conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path == "/filter-error"
    return error("a filter failed")
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
