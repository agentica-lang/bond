## The app: routes and filters, and how a request goes through them.

import Conns from "conn"
import Pattern from "pattern"
import {Conn, Handler} from "conn"

NOT_FOUND = "not found"

## Routes are tried in the order they were added. Filters run in the order they were added.
export struct App
  routes: List[Route]
  before_filters: List[Handler]
  after_filters: List[Handler]
end

struct Route
  method: String
  pattern: String
  handler: Handler
end

struct Hit
  route: Route
  params: Map[String, String]
end

export def app() -> App
  return App(routes: [], before_filters: [], after_filters: [])
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
## filter or handler, and a runtime error in one, is a 500 (a 400 for `bad_request`), and so is a response the
## server would refuse (`Conns.to_response`). The chain runs in a task of its own so that a runtime error ends the
## request and not the program; the after filters do not run for a crash.
export def handle(app: App, request: HttpRequest) -> HttpResponse
  conn = Conns.from_request(request)
  task = Task.spawn() do serve(app, conn) end
  case Task.await(task)
    ok(done) -> return Conns.to_response(done)
    error(message) -> return Conns.to_response(failure(conn, message))
  end
end

# A bad pattern is a mistake of the program, so it stops at the start and not at the first request.
def route(app: App, method: String, pattern: String, handler: Handler) -> App
  if not Pattern.valid?(pattern)
    bad: Result[App] = error("bond: the route pattern #{pattern} must start with / and name each param once")
    return bad.unwrap!
  end

  return app.with(routes: app.routes.push(Route(method: method, pattern: pattern, handler: handler)))
end

def serve(app: App, conn: Conn) -> Result[Conn]
  filtered = app.before_filters.reduce(conn) do |acc, filter| apply(acc, filter) end
  routed = dispatch(app, filtered)
  return ok(app.after_filters.reduce(routed) do |acc, filter| run(acc, filter) end)
end

# The route that matches the path and the method; a 405 when only the path matches, a 404 when nothing does. HEAD
# uses the route of GET (the server drops the body). Patterns and paths are compared as written, without decoding.
def dispatch(app: App, conn: Conn) -> Conn
  if conn.halted
    return conn
  end

  hits: List[Hit] = []
  for candidate in app.routes
    matched = Pattern.matches(candidate.pattern, conn.path)
    if matched.ok?
      # `unwrap!` cannot halt here: the result is ok.
      hits = hits.push(Hit(route: candidate, params: matched.unwrap!))
    end
  end

  if hits.empty?
    return Conns.halt(conn, 404, NOT_FOUND)
  end

  wanted = conn.method
  if wanted == "HEAD"
    wanted = "GET"
  end

  chosen = hits.select do |hit| hit.route.method == wanted end
  if chosen.empty?
    return Conns.halt(Conns.header(conn, "allow", allowed(hits)), 405, "method not allowed")
  end

  return apply(conn.with(params: chosen[0].params), chosen[0].route.handler)
end

# The methods of the routes that match the path, in the order they were added, with HEAD after GET.
def allowed(hits: List[Hit]) -> String
  methods: List[String] = []
  for hit in hits
    methods = methods.push(hit.route.method)
    if hit.route.method == "GET"
      methods = methods.push("HEAD")
    end
  end

  return methods.uniq.join(", ")
end

# A halted conn skips the handler.
def apply(conn: Conn, handler: Handler) -> Conn
  if conn.halted
    return conn
  end

  return run(conn, handler)
end

def run(conn: Conn, handler: Handler) -> Conn
  case handler.call(conn)
    ok(next_conn) -> return next_conn
    error(message) -> return failure(conn, message)
  end
end

# The message of a 500 goes to stderr and never to the client.
def failure(conn: Conn, message: String) -> Conn
  if message.start_with?(Conns.BAD_REQUEST)
    return Conns.halt(conn, 400, message.slice(Conns.BAD_REQUEST.length, message.length - Conns.BAD_REQUEST.length))
  end

  IO.warn("bond: #{conn.method} #{conn.path}: #{message}")
  return Conns.halt(conn, 500, Conns.INTERNAL_ERROR)
end
