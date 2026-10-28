# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Bond.app`, with `get`, `post`, `put`, `patch` and `delete` routes: `:name` segments give params, a path with no route is a 404, and a path with a route for other methods is a 405 with an `Allow` header.
- `Bond.Conn`, an immutable connection with the request and the response being built, and the helpers `text`, `json`, `halt`, `header`, `param`, `param_int` and `request_header`.
- `Bond.before` and `Bond.after` filters, and `Bond.log_request`.
- A handler or filter that gives `error(...)` is a 500 with a fixed text; an `error` that starts with `bad request: ` is a 400 (`param_int` gives one for text that is not a number).
- `Bond.run`, over the HTTP server of `std/http`, and `Bond.start`, `local_port`, `wait` and `stop` for a server on port 0.
- `Testing.request` (`pkg/bond/testing`) runs an app in process, with no socket.
- The behavior is specified as Gherkin features in `specs/`, run by `agentica test`.
- Needs Agentica 0.14.0 (CI and README).
