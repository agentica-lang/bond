# Bond

A small web framework for [Agentica](https://github.com/agentica-lang/agentica), in the spirit of Sinatra.
Work in progress: this is the first version, with the router, filters, custom handlers and the helpers to answer. Query and form
parsing, JSON bodies, cookies and static files come later (see
[the design](https://github.com/agentica-lang/bond/issues/1)).

Needs Agentica 0.14.0 or later.

## Install

In your `agentica.toml`:

```toml
[dependencies]
bond = { git = "https://github.com/agentica-lang/bond", ref = "COMMIT" }
```

There is no release yet, so pin a commit (`--ref COMMIT`, the whole id) until the first tag. Then
`agentica add bond https://github.com/agentica-lang/bond --ref COMMIT` (or `agentica install` for a manifest you
edited) writes `agentica.lock` and `deps/bond/`.

## Example

```ruby
import Bond from "pkg/bond/bond"

struct Todo
  id: Int
  title: String
end

struct Store
  todos: ATS[Int, Todo]
  next_id: ATS[String, Int]     # ATS.add(key, n) is atomic: use it for ids
end

def show_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")          # not a number: 400
  case store.todos.get(id)
    ok(todo) -> return ok(Bond.json(conn, 200, JSON.from(todo)))
    error(_) -> return ok(Bond.halt(conn, 404, "not found"))
  end
end

def create_todo(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.body.empty?
    return Bond.bad_request("title is empty")
  end

  todo = Todo(id: store.next_id.add("todo", 1), title: conn.body)
  store.todos.put(todo.id, todo)
  return ok(Bond.json(conn, 201, JSON.from(todo)))
end

def main() -> Void
  store = Store(todos: ATS.new(), next_id: ATS.new())
  app = (
    Bond.app()
    |> Bond.before(&Bond.log_request)
    |> Bond.get("/todos/:id") do |conn| show_todo(store, conn) end
    |> Bond.post("/todos") do |conn| create_todo(store, conn) end
    |> Bond.not_found() do |conn| ok(Bond.text(conn, 404, "there is nothing at #{conn.path}")) end
  )
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

The full program is [examples/todos.agc](examples/todos.agc).

The app does not hold your state: a handler gets it from a closure, as `store` above. That is simpler than
making the app generic over the state.

## Routes

`Bond.get`, `post`, `put`, `patch` and `delete` take the app, a pattern and a handler, and return the app, so they
chain with `|>`. A handler is `Fn[Bond.Conn, Result[Bond.Conn]]`: `&name` for a function that has only the `Conn`,
a block for one that needs more.

- A segment that starts with a colon, as in `/users/:id/posts/:post_id`, matches one segment. Read it with
  `Bond.param(conn, "id")` (a `Result[String]`) or `Bond.param_int(conn, "id")`. Neither the params nor the literal
  segments are decoded (`%20` stays `%20`, and a `/café` route never matches `/caf%C3%A9`) until `std/uri` is in
  Agentica.
- Routes are tried in the order they were added, so put `/todos/latest` before `/todos/:id`.
- A trailing slash does not matter: `/todos/` is `/todos`.
- A path with no route is a 404 with the body `not found` (see `Bond.not_found` below). A path with a route for other methods only is a 405 with
  an `Allow` header that lists the methods.
- `HEAD` uses the route of `GET` (the server drops the body), and `Allow` lists `HEAD` where it lists `GET`.
  `OPTIONS` is not answered by Bond: it is a 405 unless you add the route.
- A pattern must start with `/` and name each param once, or the program stops when the route is added.

## Conn

`Bond.Conn` is an immutable struct. The request: `method`, `path`, `query` (the raw text after `?`), `params`,
`headers` (names in lowercase) and `body`. The response being built: `status` (200 at first), `response_headers`,
`response_body` and `halted`. Every helper returns a new `Conn`:

| Function | Does |
|---|---|
| `Bond.text(conn, status, text)` | answers plain text; sets `Content-Type`, so call `header` after it for another |
| `Bond.html(conn, status, text)` | answers HTML; sets `Content-Type`. The text is sent as it is, with no escaping (Bond has no escaping yet): escape what a client sent before you put it in `text` |
| `Bond.json(conn, status, value)` | answers `value` (a `Json`, such as `JSON.from(todo)`) as JSON; sets `Content-Type` |
| `Bond.status(conn, code)` | sets the status and nothing else |
| `Bond.redirect(conn, location)` | answers a 302 with a `Location` header and no body, and halts. `Bond.redirect(conn, location, code)` takes 301, 303, 307 or 308 as well; another code stops the program with an error |
| `Bond.halt(conn, status, text)` | answers plain text and stops the filters and the handler that come after |
| `Bond.header(conn, name, value)` | sets a response header |
| `Bond.request_header(conn, name)` | the first value of a request header, as a `Result[String]` |
| `Bond.param(conn, name)` | the text of a `:name` segment, as a `Result[String]` |
| `Bond.param_int(conn, name)` | the same, as a whole number; text that is not one is a 400 |
| `Bond.bad_request(message)` | an `error` that makes a 400 with `message` as its body |

## Filters and errors

`Bond.before(app, filter)` runs a filter before the route, `Bond.after(app, filter)` after it. A filter is a
handler too. They run in the order they were added. A `before` filter that halts, or gives an error, skips the
filters and the handler after it; the `after` filters still run, for a halted answer and for a 404 too.
`Bond.log_request` is a `before` filter that writes `METHOD /path` to stderr.

A handler or filter that gives `error(message)` makes a 500 with the body `Internal Server Error`. The message
goes to stderr, never to the client. `Bond.bad_request(message)` is the error that makes a 400 with `message` as
its body.

A runtime error in a handler or filter (an index out of range, an `unwrap!` of an error) is a 500 too, and does not
stop the program. The request runs in a task of its own, and the crash of the task is the error; the `after`
filters do not run for it. The VM prints the stack trace of the crash on stderr and Bond adds one line with the
method and the path.

### Custom handlers

Like `not_found do ... end` and `error do ... end` of Sinatra:

```ruby
app = (
  Bond.app()
  |> Bond.not_found() do |conn| ok(Bond.html(conn, 404, "<h1>Nothing at the path</h1>")) end
  |> Bond.on_error() do |conn, message| ok(Bond.html(conn, 500, "<h1>Something went wrong</h1>")) end
)
```

- `Bond.not_found(app, handler)` answers a path with no route, in place of the plain `not found`. The handler is
  an ordinary handler; it gets the `Conn` with the status 404 and the `after` filters run after it. It does not
  answer a 405, and not a 404 that a handler gives itself (`Bond.halt(conn, 404, ...)`).
- `Bond.on_error(app, handler)` answers a failure (an `error` or a crash in a handler or filter, a `not_found`
  handler included) in place of the plain 500. The handler gets the `Conn`, with the status 500, and the message
  of the failure. Bond has already written the message to stderr, and nothing sends it to the client unless the
  handler does: keep it out of the answer.
- If the error handler gives an `error` or crashes, the answer is the plain 500 (and a line on stderr). It is
  never called for a `bad_request` (a 400), nor for a response that the server would refuse (see below): those
  stay plain.
- Both are set once per app; a second call replaces the first.

A response that the HTTP server of `std/http` would refuse is a plain 500, with a warning on stderr: a status outside
200 to 599, or a `Content-Length` or `Transfer-Encoding` header (the server sets them). A 204 or 304 loses its
body. `Testing.request` does the same, so a test sees what a client would.

## Running

`Bond.run(app, host, port)` serves the app with the HTTP server of `std/http` and returns when it closes.
`Bond.start(app, host, port)` returns the server at once; with port 0 it picks a free port, and
`Bond.local_port(server)` says which. `Bond.wait(server)` waits for it and `Bond.stop(server)` closes it. The
server belongs to the task that started it: call it from `main`.

`Bond.run_with(app, host, port, options)` and `Bond.start_with(app, host, port, options)` take the options of the
server of `std/http` (`HttpServerOptions`: `request_timeout_ms`, `idle_timeout_ms`, `max_connections` and
`max_body_bytes`); the others use `HTTP.server_options()`:

```ruby
import HTTP from "std/http"

options = HTTP.server_options().with(max_body_bytes: 4_194_304)
Bond.run_with(app, "127.0.0.1", 4567, options).unwrap!
```

A body over `max_body_bytes` is a 413 from the server, and never reaches the app.

## Testing an app

`Testing.request` runs an app in process, with no socket, through the same filters and routes:

```ruby
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  response = Testing.request(app, "GET", "/hello", [], "")
  puts("#{response.status} #{response.body}")   # 200 hello
end
```

Its arguments are the app, the method, the path (with its query, if any), the request headers and the body. It
gives an `HttpResponse`. A `HEAD` request is answered with the body, which the server would drop.

## Development

The tests are BDD first: the behavior is a Gherkin scenario in `specs/*.feature`, run by `agentica test`. The steps
(`specs/steps.agc`) drive the app of `specs/fixtures/app.agc` through `Testing.request`; only `server.feature` opens
a socket, on 127.0.0.1 and a free port. `test/` has the unit test of the route pattern matcher.

```sh
for file in *.agc src/*.agc examples/*.agc specs/*.agc specs/fixtures/*.agc test/*.agc; do agentica check "$file"; done
agentica test
```

`agentica test --only TEXT` runs the scenarios whose name contains `TEXT`. CI pins the Agentica release in
`.github/workflows/ci.yml` (`AGENTICA_VERSION`, with its sha256).

## License

Apache License 2.0. See [LICENSE](LICENSE).
