# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- `Bond.body_text` reads the body in its `charset` as `HTTP.text` of Agentica
  0.19.0 does (Latin-1, Windows-1252, UTF-16 and UTF-32 now decode); a charset
  it cannot decode is still a 400.

## [0.4.0] - 2026-10-31

Needs Agentica 0.19.0-beta.3 or later, which has `HTTP.StreamResponse(length:)` (agentica-lang/agentica#872) and the removal of `HTTP.server_options()` and `HTTP.client_options()` (agentica-lang/agentica#888).

### Added

- `Bond.send_file(conn, path, attachment)` answers with a file read in pieces by a task, with `Content-Length` of its size, the type of `std/mime`, `Accept-Ranges: bytes` and `X-Content-Type-Options: nosniff`. `some(name)` as `attachment` adds `Content-Disposition: attachment`. A `Range` of one range is a `206` with `Content-Range`, a range that starts beyond the end is a `416`, and `HEAD` gets the headers with the length. It sets the status (200, or 206 and 416 for a range), so call `Bond.status` after it for a page with another status.
- `Bond.stream(conn, status, body, length)` takes the size of the body when it is known: `Content-Length` and no chunks.

### Changed

- **Breaking:** the default `max_bytes` of `Bond.static` is 1 GiB (it was 1 MiB), and the most is 1 TiB. `Bond.static` sends its files with `send_file`, so a file is no longer read whole: a file between 1 MiB and 1 GiB under a static root is now served (it used to be a 500 through the error handler). Pass `max_bytes` to keep a smaller limit. Static files also have `Accept-Ranges` and ranges.
- `Testing.request` adds the `Content-Length` header to the answer of a stream that has a length, and a `HEAD` request for a static file has no body there (as over a socket).
- **Breaking:** needs Agentica 0.19.0-beta.3, which removes `HTTP.server_options()` and `HTTP.client_options()`. The options of `Bond.start_with` and `run_with` are an `HttpServerOptions`: write `HttpServerOptions(max_body_bytes: 4_194_304)` for `HTTP.server_options().with(max_body_bytes: 4_194_304)`. `Bond.start`, `run` and the examples use `HttpServerOptions()`, and the specs use `HTTP.client()` (#28).

## [0.3.0] - 2026-10-31

Needs Agentica 0.19.0-beta.2 or later.

### Added

- `Bond.static` serves any file, as the bytes it holds: images, fonts, archives and PDFs, with the type of `std/mime` (a text type gets `; charset=utf-8`, any other type is sent as it is, and a file that `std/mime` does not know is `application/octet-stream`). It reads with `File.read_bytes`, so `max_bytes` still holds (1 MiB at most).
- `Bond.bytes(conn, status, body)` answers `Bytes` as they are, and `Bond.body_text(conn)` reads the body of the request as text (UTF-8 only, a 400 with a fixed message for a body that does not decode or a `charset` other than `utf-8`).
- `Testing.text(response)` reads the body of a response as text, and `Testing.request_bytes` sends a request body that is `Bytes`.

### Changed

- **Breaking:** needs Agentica 0.19.0-beta.2 (the bodies of `std/http` are `Bytes`). `conn.body` and `conn.response_body` are `Bytes`: read the request as text with `Bond.body_text(conn)`, and the body of an `HttpResponse` from `Testing.request` with `Testing.text(response)`. `Bond.text`, `html`, `json` and `halt` still take text. A handler that used `conn.body` as text now calls `try Bond.body_text(conn)`; `Bond.json_body` and the form readers need no change. A request body that is not UTF-8 reaches the handler (before, the server answered 400), so `form_params` and `json_body` give their own 400 for it.
- `Testing.request` reads a stream that is not UTF-8 as bytes (before, the body was a 500 that said `the stream is not UTF-8 text`).
- A static file over `max_bytes` is still a 500, and a text file that is not UTF-8 is no longer a failure (it is sent as it is).

### Removed

- The 501 for a static file that is not text, and the notice about it on stderr.

## [0.2.0] - 2026-10-30

Needs Agentica 0.19.0-beta.1 or later.

### Added

- `Bond.json_as(conn, status, JSON.codec(Todo), todo)` answers a struct as JSON and encodes it once, with no `Json` in between. A generic function cannot call `JSON.encode` on its type parameter, so it takes the codec, as `json_body` does. `Bond.json` still takes a `Json`, for a list or a map.
- `Bond.stream(conn, status, channel)` and `Bond.sse(conn, channel)` answer with the pieces a task sends on a `Channel[Bytes]`, sent as they come (server-sent events for `sse`, with `Bond.sse_event(data, event)` to make each one). `Testing.request` reads the channel into the body, and `max_pieces` and `timeout_ms` (the time for the whole body) cut a stream that never ends; it reads text streams only for now (a stream that is not UTF-8 is a 500). A body that is not a stream is sent as before.

### Changed

- **Breaking:** needs Agentica 0.19.0-beta.1 or later (the streamed server; 0.18.0 for `Map.get` and `String.index_of` giving an `Optional`). `Bond.param` of a missing segment is still an `error`.
- `Bond.run` and `start` serve with `HTTP.listen_stream`; an answer that is not a stream is one closed piece, so it is sent with `Content-Length` as before.
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

[unreleased]: https://github.com/agentica-lang/bond/compare/0.4.0...HEAD
[0.4.0]: https://github.com/agentica-lang/bond/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/agentica-lang/bond/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/agentica-lang/bond/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/agentica-lang/bond/releases/tag/0.1.0
