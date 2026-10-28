## A todo list over HTTP. Run it with `agentica examples/todos.agc` and try:
##
##   curl -X POST -d 'buy milk' http://127.0.0.1:4567/todos
##   curl http://127.0.0.1:4567/todos/1

import Bond from "../bond"

PORT = 4567

struct Todo
  id: Int
  title: String
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]
end

def main() -> Void
  store = Store(todos: ATS.new(), next_id: ATS.new())
  app = (
    Bond.app()
    |> Bond.before(&Bond.log_request)
    |> Bond.get("/todos") do |conn| list_todos(store, conn) end
    |> Bond.get("/todos/:id") do |conn| show_todo(store, conn) end
    |> Bond.post("/todos") do |conn| create_todo(store, conn) end
  )
  Bond.run(app, "127.0.0.1", PORT).unwrap!
end

def list_todos(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.json(conn, 200, JSON.from(store.todos.to_map.values)))
end

def show_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  case store.todos.get(id)
    ok(todo) -> return ok(Bond.json(conn, 200, JSON.from(todo)))
    error(_) -> return ok(Bond.halt(conn, 404, "not found"))
  end
end

# The body is the title. A JSON body waits for `JSON.codec` (Agentica 0.15.0).
def create_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  todo = Todo(id: store.next_id.add("todo", 1), title: conn.body)
  store.todos.put(todo.id, todo)
  return ok(Bond.json(conn, 201, JSON.from(todo)))
end
