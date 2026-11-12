## A todo list over HTTP. Run it with `agentica examples/todos.agc` and try:
##
##   curl -X POST -H 'content-type: application/json' -d '{"title": "buy milk"}' http://127.0.0.1:4567/todos
##   curl http://127.0.0.1:4567/todos/1

import Bond from "../bond"

PORT = 4567

struct Todo
  id: Int
  title: String
end

struct NewTodo
  title: String
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]
end

def main() -> Void
  store = Store(todos: ATS.new(), next_id: ATS.new())
  on_get_root = handler() do |conn| ok(Bond.redirect(conn, "/todos")) end
  on_get_todos = handler() do |conn| list_todos(store, conn) end
  on_get_todos_id = handler() do |conn| show_todo(store, conn) end
  on_post_todos = handler() do |conn| create_todo(store, conn) end

  app = (
    Bond.app()
    |> Bond.before(&Bond.log_request)
    |> Bond.get("/", on_get_root)
    |> Bond.get("/todos", on_get_todos)
    |> Bond.get("/todos/:id", on_get_todos_id)
    |> Bond.post("/todos", on_post_todos)
    |> Bond.not_found() do |conn| ok(Bond.text(conn, 404, "there is nothing at #{conn.path}")) end
  )

  Bond.run(app, "127.0.0.1", PORT).unwrap!
end

# Gives a `do` block the type of a handler, so that a name can hold it before the pipeline that uses it (master refuses
# a chain after the `end` of a block).
def handler(f: Bond.Handler) -> Bond.Handler = f

def list_todos(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.from(store.todos.to_map.values)))
end

def show_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  case store.todos.get(id)
    ok(todo) -> ok(Bond.json_as(conn, 200, Todo.codec, todo))
    error(_) -> ok(Bond.halt(conn, 404, "not found"))
  end
end

# The body is JSON: `{"title": "buy milk"}`. A body that is not, or has no title, is a 400.
def create_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  input = try Bond.json_body(conn, NewTodo.codec)
  return Bond.bad_request("title is empty") if input.title.empty?

  todo = Todo(id: store.next_id.add("todo", 1), title: input.title)
  store.todos.put(todo.id, todo)
  ok(Bond.json_as(conn, 201, Todo.codec, todo))
end
