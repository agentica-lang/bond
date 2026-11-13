# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Needs Agentica 0.31.0 or later.

### Changed

- **Breaking:** needs Agentica 0.31.0 or later: the sources use `private` (a file is public above a `private` line, so `export` before a declaration is gone), the nested builtin names (`JSON.Value` is the type that `Bond.json` takes and that `Conn.assigns` holds; `File.Info`, `File.Handle`, `TCP.Socket`) and the errors with kinds. The public names of Bond do not change. CI tests with Agentica 0.31.0.
- `agentica.toml` says `agentica = "0.31.0"`, so an older Agentica stops with `PKG-AGENTICA-TOO-OLD` and not with a parse error at the first `private`.
- `Bond.set_cookie_with` and `Bond.assigned` keep the kind, the code and the cause of the error they pass on (`argument` for a refused cookie), and still put their own text in front of the message.
- The handler of `Bond.on_error` still gets the message as a `String`. An upload body that the server cuts is still answered 413, 431 or 400, now from the kind and the code of the error (`http.too_large`) and not from its text.

## [0.12.0-alpha.1] - 2026-11-12

Needs Agentica 0.31.0-alpha.1 or later.

### Changed

- **Breaking:** needs Agentica 0.31.0-alpha.1 or later: the sources, the examples and the guide use the HTTP types of `std/http` (`HTTP.Header`, `HTTP.Request`, `HTTP.Response`, `HTTP.Server`, `HTTP.ServerOptions`), which are now the only names of those types. CI tests with Agentica 0.31.0-alpha.1.

## [0.11.0] - 2026-11-12

Needs Agentica 0.30.0 or later.

### Changed

- The sources, the examples and the code samples of the guide never chain a call, an index or a pipe after the `end` of a `do` block, which the next Agentica refuses (`CHECK-CHAIN-AFTER-END`). The behavior does not change.
- **Breaking:** needs Agentica 0.30.0 or later: the sources are formatted with `agentica fmt`, which uses the syntax of 0.29.0 (implicit returns, guards, one-line defs). CI tests with Agentica 0.30.0.

## [0.10.1] - 2026-11-08

Needs Agentica 0.27.0 or later.

### Changed

- Faster files: `Bond.send_file` and `Bond.static` set the headers of an answer in one call instead of one by one, with the same headers in the same order.
- Faster static files and answers: `Bond.header` and `Bond.request_header` no longer lowercase every header name they compare, with the same results.

## [0.10.0] - 2026-11-08

Needs Agentica 0.27.0 or later.

### Changed

- **Breaking:** Bond needs Agentica 0.27.0 or later: it signs session cookies with `OpenSSL.HMAC` and makes upload folder names with `OpenSSL.Random` (`HMAC` and `SecureRandom` are gone in 0.27.0). CI tests with Agentica 0.27.0.

## [0.9.0] - 2026-11-08

Needs Agentica 0.25.0 or later.

### Changed

- **Behaviour:** a served answer (`Bond.run`, `Bond.start`) is no longer checked a character at a time in Agentica: the server of `std/http` checks the status, the length and the header names and values in C when it writes the head, so a response with ten headers is cheaper to send. An answer it refuses (a CR, LF or NUL in a value, a name that is not a token, a `Content-Length`) is now the server's 500 with no body, `Connection: close` and the reason on stderr, and none of its bytes or of a stream are sent. `Testing.request` keeps the checks and the plain 500, as does a `Location` that is not ASCII.

## [0.8.0] - 2026-11-06

Needs Agentica 0.25.0 or later.

### Added

- The documentation site has a version selector: one site per release (`/bond/0.7.0/`, ...), the latest at the root and `dev` for the main branch, with a banner on old and development pages.

### Changed

- **Breaking:** Bond needs Agentica 0.25.0 or later. `Bond.json_as`, `Bond.json_body` and `Bond.assigned` take a `Codec[T]` instead of a `JSON.Codec[T]`, and you pass `User.codec` instead of `JSON.codec(User)` (`Bond.json_body(conn, User.codec)`).
- CI tests with Agentica 0.25.0.

## [0.7.0] - 2026-11-06

Needs Agentica 0.22.0 or later. `Testing` (`pkg/bond/testing`) needs 0.23.0 or later, as in 0.6.x: its defaults name a constant.

### Added

- `Bond.send_file` answers with an `ETag` and a `Last-Modified`, and a `GET` or `HEAD` with a matching `If-None-Match`, or with an `If-Modified-Since` (in the three forms of RFC 9110) that is not before the change, is a 304 with no body (`If-None-Match` wins). It takes `max_age: Optional[Int] = none` for `Cache-Control` (`some(0)` is `no-cache`, `some(n)` is `private, max-age=n`, or `public, max-age=n` with `public: true`) and `piece_bytes: Int = 65_536` (4 KiB to 16 MiB). With no `max_age`, a `Cache-Control` already on the conn is kept, and otherwise it is `no-cache`, so a browser does not keep the file by the new `Last-Modified` alone.
- `Bond.static` sends `Last-Modified`, answers `If-Modified-Since`, and takes `cache_bytes: Int = 16_777_216` (0 for none) and `piece_bytes: Int = 65_536` (4 KiB to 16 MiB). A file of at most `piece_bytes` is kept in memory: a hit costs one `stat` (two for a text file and a client that takes gzip, the second for its `.gz` path), and a file with another size or time of change, or with a `.gz` that changed, came or went, is read again.
- `Bond.static` sends a text file gzipped, with `Content-Encoding: gzip`, `Vary: Accept-Encoding` and its own `ETag`, to a client that takes gzip and asks for the whole file, when a `.gz` file sits next to it that is not older than the file and is inside the folder by the same rules as the file. Bond compresses nothing at run time: the build makes the `.gz`.

### Changed

- **Behaviour:** `Bond.static` answers with `Last-Modified` and honours `If-Modified-Since`, and a text file with a `.gz` next to it (one made for another server, say) is now sent gzipped to a client that takes gzip.
- **Behaviour:** the answer of `Bond.send_file` has a `Cache-Control` when the conn has none: `no-cache`, so a cache asks each time as it did when there was no validator. A `Cache-Control` set on the conn before the call is kept, and `max_age` sets it.
- A file of at most `piece_bytes` (64 KiB by default) is read in one call and answered as a plain body, with no task and no channel; a bigger one is still sent in pieces. `Bond.static` does 1 `stat` of the file where it did 3 for a file that is not kept, and none of the lookup of the path for a file that is. The status, the headers and the bytes of a range are the same.
- The check of the response headers (the rule that refuses a bad name, a control character or a non-Latin-1 value is the same) uses a set of the allowed characters, and skips the names and values that Bond writes itself, so it costs a fraction of the steps for each answer.
- `Testing.request` shows `Content-Length` for a file that `send_file` answers whole, as for a streamed one.
- CI tests with Agentica 0.24.1 and runs `agentica test --jobs` (`make test`). Bond still needs 0.22.0 or later; only developing Bond needs 0.24.1.

## [0.6.1] - 2026-11-04

Needs Agentica 0.22.0 or later.

### Fixed

- Bond checks clean on the next Agentica release, where unused imports and variables and dropped `Result`s are errors: the unused imports are removed, the unused block parameters are renamed `_conn`, and the best-effort cleanup calls discard their result with `_ =`. Nothing changes in behaviour.

## [0.6.0] - 2026-11-04

Needs Agentica 0.22.0 or later (`HttpRequest.remote_addr`).

### Added

- `Bond.assign(conn, key, value)` keeps a value of the request for the filters and the handler that come after (the person a sign-in filter loaded, so the handler does not load them again), and `Bond.assigned(conn, key, JSON.codec(Person))` reads it back as a `Result` of that type: an `error` when nothing was assigned under `key` or the value has another type; `Bond.assigned?(conn, key)` asks whether there is one. `Conn` has a new field `assigns: Map[String, Json]` with a default (`{}`), so code that builds a `Conn` by hand still compiles; this is not a breaking change. The guide has a section on it.

- `Conn.remote_addr` is the IP address of the client (`HttpRequest.remote_addr` of Agentica 0.22.0 or later), with no port. Behind a proxy it is the proxy's address: Bond does not trust `X-Forwarded-For`. The field has a default (`""`), so code that builds a `Conn` by hand still compiles; this is not a breaking change. `Testing.request` and `Testing.request_bytes` take a `remote_addr` argument, `Testing.LOOPBACK` (`"127.0.0.1"`) by default, and `Testing.request_from(app, remote_addr, method, target, headers, body)` chooses the address first, without restating the stream bounds. The guide has a section on it.

## [0.5.0] - 2026-11-03

Needs Agentica 0.22.0 or later (EAG `escape` directive, `HTTP.serve` and `HTTP.body_refusal`).

### Added

- `Bond.uploads(app, options)` reads the `multipart/form-data` body of a POST, PUT or PATCH as it arrives: its text fields go to `Bond.form` and its files to a private temporary folder, given by `Bond.file` and `Bond.file_all` as `Bond.UploadedFile` (field, safe filename, content type, path, size) and removed after the answer. The body is read after the before filters, only for a request that found its route. A file over `max_file_bytes`, a text field over `max_field_bytes`, the text fields over `max_fields_bytes` or a body over `max_total_bytes` (`Bond.UploadOptions`) is a 413. The guide has a page on it.

- `Bond.websocket(app, pattern, handler)` adds a WebSocket route on the server of the app, so a page, a stream and a WebSocket share one port. The handler gets the `Conn` of the handshake (params, session) and the `HTTP.WebSocket`. A handshake from another site's page is a 403 (its `Origin` must name the host, or be one of `allowed_origins`), and a request that does not ask for the upgrade is a 426. A quiet WebSocket is pinged after 30 s and dropped after 120 s (`Bond.WEBSOCKET_OPTIONS`), since each open one holds a connection of the server. The guide has a page on it.

- A guide page, Views, on pages, partials and a layout built from EAG templates with `Bond.escape` and `Bond.html`. There is no new function: a view is a function that returns a `String`, and a layout takes the inner HTML.

- `Bond.escape(text)` escapes `&`, `<`, `>`, `"` and `'` for HTML (it is `HTML.escape` of `std/html`). An EAG template of Agentica 0.22.0 can start with `<%@ escape &Bond.escape %>` to escape every `<%= %>`; `<%== %>` stays raw. The guide has a section on it.

- `Bond.sessions(app, options)` keeps a session in a cookie signed with HMAC-SHA256: `Bond.session`, `Bond.get_session`, `Bond.set_session`, `Bond.delete_session` and `Bond.clear_session`, `Bond.SessionOptions` (`secret`, `old_secrets` to rotate it, `name`, `max_age`, `secure`, `same_site`, `path`, `domain`; always `HttpOnly`) and `Testing.session_cookie`. A changed, expired or unknown cookie is an empty session.
- **Breaking:** `Conn` has two new fields with no default, `session` and `session_changed`: code that builds a `Conn` by hand must set them.

- `Bond.csrf(app, allowed_origins)` refuses with a 403 an unsafe request (not `GET`, `HEAD` or `OPTIONS`) that comes from another site, by `Sec-Fetch-Site` and `Origin`, with no token in the forms.

### Changed

- `Bond.static` answers every file with an `ETag` (size and time of change) and a `Cache-Control`, and a `GET` or `HEAD` with a matching `If-None-Match` is a 304 with no body. They are `no-cache`, or `public, max-age=<max_age>` with the new `max_age` argument (0 to a year, 0 by default). With the new `fingerprint: true`, a name with a hash in it (`app.3f9a1c2b.css`) is `public, max-age=31536000, immutable`.
- `Bond.body_text` reads the body in its `charset` as `HTTP.text` of Agentica
  0.19.0 does (Latin-1, Windows-1252, UTF-16 and UTF-32 now decode); a charset
  it cannot decode is still a 400.
- **Breaking:** needs Agentica 0.22.0, which removed `HTTP.listen_stream` and
  the other `listen` forms. `Bond.start`, `start_with`, `run` and `run_with`
  serve with `HTTP.serve` and keep their signatures, so a program that calls
  them needs no change. The body is read whole (up to `max_body_bytes`) before
  the app runs, as before. A refused body is now answered by
  `HTTP.body_refusal`: 413 over the limit, 431 for a chunk line that is too
  long, 400 for a bad chunk, all with `Connection: close`; a client that
  leaves gets no answer.
- CI now tests with Agentica 0.23.0. Bond still needs 0.22.0 or later.

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

[unreleased]: https://github.com/agentica-lang/bond/compare/0.12.0-alpha.1...HEAD
[0.12.0-alpha.1]: https://github.com/agentica-lang/bond/compare/0.11.0...0.12.0-alpha.1
[0.11.0]: https://github.com/agentica-lang/bond/compare/0.10.1...0.11.0
[0.10.1]: https://github.com/agentica-lang/bond/compare/0.10.0...0.10.1
[0.10.0]: https://github.com/agentica-lang/bond/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/agentica-lang/bond/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/agentica-lang/bond/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/agentica-lang/bond/compare/0.6.1...0.7.0
[0.6.1]: https://github.com/agentica-lang/bond/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/agentica-lang/bond/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/agentica-lang/bond/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/agentica-lang/bond/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/agentica-lang/bond/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/agentica-lang/bond/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/agentica-lang/bond/releases/tag/0.1.0
