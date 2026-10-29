## The app: routes and filters, and how a request goes through them.

import Conns from "conn"
import Pattern from "pattern"
import Router from "router"
import Statics from "static"
import {Conn, ErrorHandler, Handler} from "conn"

NOT_FOUND = "not found"

## Routes are kept as a tree of segments (`router.agc`): a literal segment wins over a param, whatever the order the
## routes were added in. Filters run in the order they were added. `not_found` answers a
## path with no route and `on_error` a failure; `app()` sets the plain answers.
export struct App
  routes: Router.Node
  before_filters: List[Handler]
  after_filters: List[Handler]
  statics: List[Statics.Mount]
  notes: ATS[String, Bool]
  not_found: Handler
  on_error: ErrorHandler
end

export def app() -> App
  notes: ATS[String, Bool] = ATS.new()
  return App(
    routes: Router.empty(),
    before_filters: [],
    after_filters: [],
    statics: [],
    notes: notes,
    not_found: &plain_not_found,
    on_error: &plain_error,
  )
end

export def get(app: App, pattern: String, handler: Handler) -> App
  return route(app, "GET", pattern, handler)
end

export def post(app: App, pattern: String, handler: Handler) -> App
  return route(app, "POST", pattern, handler)
end

export def put(app: App, pattern: String, handler: Handler) -> App
  return route(app, "PUT", pattern, handler)
end

export def patch(app: App, pattern: String, handler: Handler) -> App
  return route(app, "PATCH", pattern, handler)
end

export def delete(app: App, pattern: String, handler: Handler) -> App
  return route(app, "DELETE", pattern, handler)
end

## Sets the handler for a path with no route. It gets the `Conn` with status 404 and answers like any handler;
## the `after` filters run after it. A path with a route for other methods is a 405 and does not come here.
export def not_found(app: App, handler: Handler) -> App
  return app.with(not_found: handler)
end

## Sets the handler for a failure: an `error` of a handler or filter, or a runtime error in one. It gets the `Conn`
## with status 500 and the message, which Bond has already written to stderr and which must stay from the client.
## If the handler gives an error or crashes, the answer is the plain 500. A `bad_request` is a 400 and does not
## come here.
export def on_error(app: App, handler: ErrorHandler) -> App
  return app.with(on_error: handler)
end

## Serves the files of the folder `root` under the path `prefix` (`Bond.static(app, "/assets", "public")`), for `GET`
## and `HEAD`. A route of the app wins over a file, and a path that is not a file of the folder (missing, a folder, a
## dot file, a way out of the folder such as `..` or `%2e%2e`, a link that leads out) is answered as a path with no
## route, so the `not_found` handler applies. A body is text: a file whose type is not text is a 501, and a text file
## over `max_bytes` (1 MiB at most, the default) or that is not UTF-8 is a failure (a 500 through the error handler).
## The program stops when `prefix` is not a path or has a `:param`, when `max_bytes` is out of range, or when `root`
## is not a folder now: it is checked when the app is built, and its real path is kept.
export def static(app: App, prefix: String, root: String, max_bytes: Int = 1_048_576) -> App
  if not Pattern.valid?(prefix) or Pattern.segments(prefix).any? do |part| part.start_with?(":") end
    bad: Result[App] = error("bond: the static prefix #{prefix} must start with / and have no :param")
    return bad.unwrap!
  end

  if max_bytes < 1 or max_bytes > Statics.MAX_FILE_BYTES
    bad: Result[App] = error("bond: max_bytes of a static folder must be 1 to #{Statics.MAX_FILE_BYTES}")
    return bad.unwrap!
  end

  real = Statics.real_root(root)
  if not real.ok?
    bad: Result[App] = error("bond: the static folder #{root} must be a folder that exists")
    return bad.unwrap!
  end

  mount = Statics.Mount(prefix: prefix, root: real.unwrap!, max_bytes: max_bytes)
  return app.with(statics: app.statics.push(mount))
end

## Adds a filter that runs before the route. A filter that halts, or gives an error, skips the filters and the
## handler that come after it.
export def before(app: App, filter: Handler) -> App
  return app.with(before_filters: app.before_filters.push(filter))
end

## Adds a filter that runs after the route. It runs for every answer, a halted one and a 404 too.
export def after(app: App, filter: Handler) -> App
  return app.with(after_filters: app.after_filters.push(filter))
end

## The response to a request: the before filters, the route, the after filters. It does not fail: an `error` of a
## filter or handler, and a runtime error in one, goes to the error handler (a 400 for `bad_request`), and a
## response the server would refuse is a plain 500 (`Conns.to_response`). The chain runs in a task of its own so
## that a runtime error ends the request and not the program; the after filters do not run for a crash.
export def handle(app: App, request: HttpRequest) -> HttpResponse
  conn = Conns.from_request(request)
  task = Task.spawn() do serve(app, conn) end
  case Task.await(task)
    ok(done) -> return Conns.to_response(done)
    error(message) ->
      # The VM has printed the stack trace of the crash; the message is not logged a second time.
      IO.warn("bond: #{conn.method} #{conn.path}: crashed, the stack trace is above")
      return Conns.to_response(answer_error(app, conn, message))
  end
end

# A bad pattern, a route added twice and a param with two names are mistakes of the program, so they stop it at the
# start and not at the first request.
def route(app: App, method: String, pattern: String, handler: Handler) -> App
  if not Pattern.valid?(pattern)
    bad: Result[App] = error("bond: the route pattern #{pattern} must start with / and name each param once")
    return bad.unwrap!
  end

  added = Router.add(app.routes, method, pattern, handler)
  if not added.ok?
    bad: Result[App] = error(added.message)
    return bad.unwrap!
  end

  return app.with(routes: added.unwrap!)
end

def serve(app: App, conn: Conn) -> Result[Conn]
  filtered = app.before_filters.reduce(conn) do |acc, filter| apply(app, acc, filter) end
  routed = dispatch(app, filtered)
  return ok(app.after_filters.reduce(routed) do |acc, filter| run(app, acc, filter) end)
end

# The node of the tree that holds the path (a literal segment before a param), then its handler for the method: a 405
# when the node has routes for other methods only, a 404 when no node has the path. HEAD uses the route of GET (the
# server drops the body). Paths are compared as written, without decoding.
def dispatch(app: App, conn: Conn) -> Conn
  if conn.halted
    return conn
  end

  found = Router.find(app.routes, conn.path)
  if not found.ok?
    case Statics.serve(app.statics, app.notes, conn)
      ok(answer) -> return answer
      error(reason) -> return unserved(app, conn, reason)
    end
  end

  hit = found.unwrap!
  wanted = conn.method
  if wanted == "HEAD"
    wanted = "GET"
  end

  if not hit.node.handlers.key?(wanted)
    return Conns.halt(Conns.header(conn, "allow", allowed(hit.node)), 405, "method not allowed")
  end

  return apply(app, conn.with(params: hit.params), hit.node.handlers[wanted])
end

# A path under no folder, or with no file, is a 404 for the not found handler; a file that cannot be sent is a failure,
# like the error of a handler.
def unserved(app: App, conn: Conn, reason: String) -> Conn
  if reason == Statics.MISS
    return run(app, conn.with(status: 404), app.not_found).with(halted: true)
  end

  return failure(app, conn, reason)
end

# The methods of the routes of the node, in the order they were added, with HEAD after GET.
def allowed(node: Router.Node) -> String
  methods: List[String] = []
  for method in node.handlers.keys
    methods = methods.push(method)
    if method == "GET"
      methods = methods.push("HEAD")
    end
  end

  return methods.uniq.join(", ")
end

# A halted conn skips the handler.
def apply(app: App, conn: Conn, handler: Handler) -> Conn
  if conn.halted
    return conn
  end

  return run(app, conn, handler)
end

def run(app: App, conn: Conn, handler: Handler) -> Conn
  case handler.call(conn)
    ok(next_conn) -> return next_conn
    error(message) -> return failure(app, conn, message)
  end
end

# The message of a failure goes to stderr and never to the client.
def failure(app: App, conn: Conn, message: String) -> Conn
  if message.start_with?(Conns.BAD_REQUEST)
    return Conns.halt(conn, 400, message.slice(Conns.BAD_REQUEST.length, message.length - Conns.BAD_REQUEST.length))
  end

  IO.warn("bond: #{conn.method} #{conn.path}: #{message}")
  return answer_error(app, conn, message)
end

# The error handler runs in a task of its own, like the chain: if it crashes, the request still gets an answer. It
# gets the request with nothing of the answer built so far, in both paths, so that no header of a filter or of the
# handler that failed is in a 500.
def answer_error(app: App, conn: Conn, message: String) -> Conn
  failing = conn.with(status: 500, response_headers: [], response_body: "")
  task = Task.spawn() do app.on_error.call(failing, message) end
  case Task.await(task)
    ok(answer) -> return answer.with(halted: true)
    error(reason) ->
      IO.warn("bond: #{conn.method} #{conn.path}: the error handler failed: #{reason}")
      return Conns.halt(failing, 500, Conns.INTERNAL_ERROR)
  end
end

def plain_not_found(conn: Conn) -> Result[Conn]
  return ok(Conns.halt(conn, 404, NOT_FOUND))
end

def plain_error(conn: Conn, message: String) -> Result[Conn]
  return ok(Conns.halt(conn, 500, Conns.INTERNAL_ERROR))
end
