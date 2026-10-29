# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Bond.app`, with `get`, `post`, `put`, `patch` and `delete` routes: `:name` segments give params, a path with no route is a 404, and a path with a route for other methods is a 405 with an `Allow` header.
- `Bond.Conn`, an immutable connection with the request and the response being built, and the helpers `text`, `json`, `halt`, `header`, `param`, `param_int` and `request_header`.
- `Bond.before` and `Bond.after` filters, and `Bond.log_request`.
- A handler or filter that gives `error(...)`, or stops with a runtime error, is a 500 with a fixed text and the message on stderr. The request runs in a task of its own. `Bond.bad_request(message)` gives an error that is a 400 (`param_int` uses it for text that is not a number).
- A response the HTTP server would refuse (a status outside 200 to 599, a `Content-Length` or `Transfer-Encoding` header, a header name that is not a token, a value with a control or non-Latin-1 character) is a 500, and a 204 or 304 loses its body, over the server and in `Testing.request` alike.
- `HEAD` uses the route of `GET`; `Allow` lists `HEAD` where it lists `GET`.
- `Bond.run`, over the HTTP server of `std/http`, and `Bond.start`, `local_port`, `wait` and `stop` for a server on port 0.
- `Testing.request` (`pkg/bond/testing`) runs an app in process, with no socket.
- The behavior is specified as Gherkin features in `specs/`, run by `agentica test`.
- `Bond.not_found` and `Bond.on_error` set the handlers for a path with no route and for a failure, in place of the plain 404 and 500. A handler of errors that fails gives the plain 500.
- `Bond.html`, `Bond.status` and `Bond.redirect` (a 302, or 301, 303, 307 and 308; it halts and drops the content type; the `Location` must be ASCII). `Bond.html` does not escape the text.
- `Bond.start_with` and `Bond.run_with` take the options of the HTTP server of `std/http` (timeouts, connections, body limit).
- A crash writes one line on stderr after the stack trace of the VM, not its message again.
- A documentation site (Hugo, GitHub Pages) in `site/`, with `make site`, and `make site-samples`, which checks (and runs, when an output block follows) every code sample of the site.
- `Bond.json_body(conn, JSON.codec(User))` decodes a JSON request body into a struct; a wrong or missing content type, an empty body or a body that does not fit is a 400 with a short message. A guide page on the site.
- Needs Agentica 0.15.0 (README and site). CI runs on Agentica 0.16.0, and the specs and the site samples pass on it.
