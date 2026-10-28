# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Bond.app`, with `get`, `post`, `put`, `patch` and `delete` routes: `:name` segments give params, a path with no route is a 404, and a path with a route for other methods is a 405 with an `Allow` header.
- `Bond.Conn`, an immutable connection with the request and the response being built, and the helpers `text`, `json`, `halt`, `header`, `param`, `param_int` and `request_header`.
- `Bond.before` and `Bond.after` filters, and `Bond.log_request`.
- A handler or filter that gives `error(...)`, or stops with a runtime error, is a 500 with a fixed text and the message on stderr. The request runs in a task of its own. `Bond.bad_request(message)` gives an error that is a 400 (`param_int` uses it for text that is not a number).
- A response the HTTP server would refuse (a status outside 200 to 599, a `Content-Length` or `Transfer-Encoding` header) is a 500, and a 204 or 304 loses its body, over the server and in `Testing.request` alike.
- `HEAD` uses the route of `GET`; `Allow` lists `HEAD` where it lists `GET`.
- `Bond.run`, over the HTTP server of `std/http`, and `Bond.start`, `local_port`, `wait` and `stop` for a server on port 0.
- `Testing.request` (`pkg/bond/testing`) runs an app in process, with no socket.
- The behavior is specified as Gherkin features in `specs/`, run by `agentica test`.
- Needs Agentica 0.14.0 (CI and README).
