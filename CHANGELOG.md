# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- `Testing.request(app, method, target)` takes the headers and the body as optional arguments (no headers, an empty body), so `Testing.request(app, "GET", "/hello")` works.
- **Breaking:** routes are kept as a tree of segments, so a lookup does not depend on the number of routes. A literal segment now wins over a `:param` at the same place whatever the order the routes were added in (before, the earlier route won); the walk goes back to the param when the literal branch has no route deeper. The method is chosen after the path, so a 405 `Allow` lists the methods of that route only. The same method and pattern twice, and two names for the param at the same place (`/users/:id` and `/users/:name/posts`), stop the program when the route is added.

## [0.1.0] - 2026-10-29

First release. Needs Agentica 0.16.0 or later.

### Added

- `Bond.app` with `get`, `post`, `put`, `patch` and `delete` routes, `:name` params, a 404 for a path with no route, and a 405 with `Allow` for a wrong method. `HEAD` uses the route of `GET`.
- `Bond.Conn`, an immutable connection, with the helpers `text`, `json`, `html`, `status`, `redirect`, `halt`, `header`, `param`, `param_int` and `request_header`.
- `Bond.before` and `Bond.after` filters, and `Bond.log_request`.
- A handler or filter that gives `error(...)` or crashes is a 500 with a fixed text and the message on stderr. `Bond.bad_request(message)` makes a 400.
- A response that the HTTP server would refuse is a 500.
- `Bond.not_found` and `Bond.on_error` set the handlers for a missing path and for a failure.
- `Bond.json_body(conn, JSON.codec(User))` decodes a JSON body into a struct; a bad body is a 400.
- `Bond.query`, `query_int`, `query_all` and `query_params` read the query string; `Bond.form`, `form_int`, `form_all` and `form_params` read a form body. A missing name, a bad number or a bad `%` is a 400.
- `Bond.cookies`, `cookie`, `set_cookie` (`Path=/`, `HttpOnly`, `SameSite=Lax`), `set_cookie_with` and `delete_cookie`.
- `Bond.static(app, prefix, root, max_bytes)` serves a folder for `GET` and `HEAD`, typed with `std/mime`, with no way out of the folder. Only text files for now: a file that is not text is a 501. No caching headers.
- `Bond.run`, `start`, `local_port`, `wait` and `stop`, and `start_with` and `run_with` with the options of the HTTP server of `std/http`.
- `Testing.request` (`pkg/bond/testing`) runs an app in process, with no socket.
- A documentation site with a guide page for each part, including one on HTML escaping with `HTML.escape`; `make site-samples` checks every sample.
- The behavior is specified as Gherkin features in `specs/`, run by `agentica test`.

[unreleased]: https://github.com/agentica-lang/bond/compare/0.1.0...HEAD
[0.1.0]: https://github.com/agentica-lang/bond/releases/tag/0.1.0
