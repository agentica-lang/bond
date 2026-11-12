---
title: Sending files
weight: 15
description: Answer with a file of any size, with its length, validators for a 304, a download name and byte ranges.
---

# Sending files

`Bond.send_file(conn, path)` answers with the file at `path`, as a `Result[Bond.Conn]`: return it or `try` it. It sets the status itself: 200, 304 for a request that already has the file (below), or 206 and 416 for a range, whatever the status was. A [custom `not_found` handler](/guide/errors/) that sends a file therefore answers 200 (and a 206 for a `Range`): call `Bond.status(conn, 404)` after `send_file` for another status.

A file of at most `piece_bytes` (64 KiB by default) is read in one call and answered as a plain body. A bigger one is read in pieces of that size by a task that the call starts while the server sends them, so a file of any size costs a few pieces of memory. The server knows the size first, so the answer has `Content-Length` and the pieces go out with no chunks (the `length` of [`Bond.stream`](/guide/streaming/)). `piece_bytes` is the last argument, 4 KiB to 16 MiB, and a value out of range is an `error`: `Bond.send_file(conn, path, none, none, false, 262_144)`.

The answer has:

- `Content-Type` from `std/mime` by the extension of the file, with `; charset=utf-8` added for a text type; an unknown extension is `application/octet-stream`.
- `Content-Length` (added by the server) and `Accept-Ranges: bytes`.
- `X-Content-Type-Options: nosniff`, so a browser does not guess a script from a text file.
- `ETag` (the size and the time of the last change in seconds, no read of the file) and `Last-Modified`.
- `Cache-Control`: `no-cache` by default (a cache keeps the file but asks each time, a cheap 304), unless the route set a `Cache-Control` on the conn before, which is kept. The fourth argument, `max_age`, sets it: `some(0)` is `no-cache` and `some(600)` is `private, max-age=600` (0 to a year). It is `private` since a route that sends a file is often for one person (an avatar, a report); `public: true` (the fifth argument) makes it `public, max-age=600`, which is right only for a file that every person may see, since a shared cache (a proxy, a CDN) keeps one copy for all.

A third argument, an `Optional[String]`, makes the file a download: `Bond.send_file(conn, "reports/q3.csv", some("q3 report.csv"))` adds `Content-Disposition: attachment; filename="q3 report.csv"`, and the browser saves it under that name. A name with a control character (CR, LF, NUL), a quote, a backslash or a character outside ASCII has a fallback `filename` (each such character is `_`) and the exact name as `filename*=UTF-8''...`, as RFC 6266 says.

The `error` of `send_file` is a path that is not a plain file (missing, a folder) or a file that cannot be opened. It goes to the [`on_error` handler](/guide/errors/) like any failure of a handler. The path is yours, not the client's: do not build one from a request without the checks that [Static files](/guide/static/) makes. The file can still change after the answer started: a file that gets shorter is cut, and the client sees an incomplete body, never a short one that looks whole.

## Conditional requests

A `GET` or `HEAD` whose `If-None-Match` lists the `ETag` (or is `*`; a `W/` prefix is ignored) is a `304 Not Modified` with the `ETag`, `Last-Modified` and `Cache-Control`, and no body. When there is no `If-None-Match` (it wins when both are sent, as RFC 9110 says), an `If-Modified-Since` that is not before the time of the change is a `304` too. The date is read in any of the three forms of RFC 9110 (`Sun, 06 Nov 1994 08:49:37 GMT`, `Sunday, 06-Nov-94 08:49:37 GMT` and `Sun Nov  6 08:49:37 1994`); any other text is ignored. The 304 is answered before the range, so a request with both gets the 304. The route runs first, so a check that a person may see the file stays in the route, and a 304 is never sent to someone it refused. An edit that keeps the size within the same second is not seen.

## Ranges

Bond answers one `Range: bytes=a-b`:

| Request | Answer |
|---|---|
| `bytes=0-99` | `206`, the first 100 bytes, `Content-Range: bytes 0-99/SIZE` |
| `bytes=100-` | `206`, from byte 100 to the end |
| `bytes=-500` | `206`, the last 500 bytes |
| `bytes=0-9999999` (past the end) | `206`, up to the end, the range cut to the file |
| `bytes=SIZE-` or more, `bytes=-0` | `416` with `Content-Range: bytes */SIZE` and no body |
| two ranges (`bytes=0-1,5-6`), a range that is not made of digits, one that ends before it starts, another unit | ignored: `200` with the whole file |

`If-Range` is not read (the `ETag` is made from the size and the time in seconds, which is weaker than the strong validator that `If-Range` needs), so the whole file is answered. `File` cannot seek, so the bytes before the start of a range are read and dropped: a range near the end of a big file reads the file up to it.

`HEAD` gets the same headers as `GET` (a 206 for a range) with the length and no body, and the file is not opened.

## An example

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def report(conn: Bond.Conn) -> Result[Bond.Conn]
  return Bond.send_file(conn, "files_sample.txt")
end

def save(conn: Bond.Conn) -> Result[Bond.Conn]
  return Bond.send_file(conn, "files_sample.txt", some("ten.txt"))
end

def show(app: Bond.App, method: String, path: String, range: String) -> Void
  headers = [HTTP.Header(name: "range", value: range)]
  response = Testing.request(app, method, path, headers)
  length = HTTP.header_values(response.headers, "content-length").join(",")
  part = HTTP.header_values(response.headers, "content-range").join(",")
  puts("#{method} #{path} #{range} -> #{response.status} #{length} #{part} #{Testing.text(response).unwrap_or("")}")
end

def main() -> Void
  File.write_text("files_sample.txt", "0123456789").unwrap!
  app = Bond.app() |> Bond.get("/report", &report) |> Bond.get("/save", &save)
  show(app, "GET", "/report", "")
  show(app, "GET", "/report", "bytes=2-4")
  show(app, "GET", "/report", "bytes=-3")
  show(app, "GET", "/report", "bytes=20-")
  show(app, "HEAD", "/report", "bytes=2-4")
  response = Testing.request(app, "GET", "/save")
  puts(HTTP.header_values(response.headers, "content-disposition").join(","))
  Path.remove("files_sample.txt").unwrap!
end
```

```output
GET /report  -> 200 10  0123456789
GET /report bytes=2-4 -> 206 3 bytes 2-4/10 234
GET /report bytes=-3 -> 206 3 bytes 7-9/10 789
GET /report bytes=20- -> 416  bytes */10 
HEAD /report bytes=2-4 -> 206 3 bytes 2-4/10 
attachment; filename="ten.txt"
```
