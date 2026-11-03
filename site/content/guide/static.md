---
title: Static files
weight: 8
description: Serve the files of a folder under a path, with the type from std/mime and no way out of the folder.
---

# Static files

`Bond.static(app, "/assets", "public")` serves the files of the folder `public` under the path `/assets`: `/assets/app.css` is the file `public/app.css`, and `/assets/img/logo.svg` is `public/img/logo.svg`. The folder is relative to the working directory of the program, or absolute (prefer absolute: a program started in another folder would not find a relative one). It must exist when the app is built, or the program stops at once, like a bad route pattern; its real path is kept from then on.

Only `GET` and `HEAD` read a file. Any other method on a path under the prefix is a 405 with `Allow: GET, HEAD`. A route of the app wins over a file: if you add `Bond.get("/assets/special.txt", ...)`, the handler answers, and the file is never read. Call `Bond.static` more than once for more folders. The first prefix that holds the path decides, so a second folder under the same prefix is never read: put the longer prefix first (`Bond.static("/assets/vendor", "vendor")` before `Bond.static("/assets", "public")`, or `/assets/vendor/x.js` is looked up in `public/vendor/`).

## What the answer has

- `Content-Type` from `std/mime` by the extension of the file (`text/css`, `application/json`, `image/png`), with `; charset=utf-8` added for a text type (`MIME.text?`). A file with an extension that `std/mime` does not know, or with none (`LICENSE`), is `application/octet-stream`.
- `X-Content-Type-Options: nosniff`, so a browser uses the type that Bond sent and does not guess a script from a text file.
- `Content-Length` (added by the HTTP server); a `HEAD` answer has the same headers and no body.
- `Accept-Ranges: bytes`, and a `Range` header is answered with a 206 or a 416, as for [`Bond.send_file`](/guide/files/), which sends every file.
- `ETag` and `Cache-Control` (below). Bond sends no `Last-Modified` and reads no `If-Modified-Since` or `If-Range`.

## Caching

Every file has an `ETag` made from its size and the time of its last change in seconds, so Bond does not read the file to make it. A `GET` or `HEAD` whose `If-None-Match` lists the tag (or is `*`) is a `304 Not Modified` with the `ETag` and the `Cache-Control`, no body, and the file is not opened. A `W/` prefix on the tag of the request is ignored (weak comparison). An edit that keeps the size and happens in the same second as the last change is not seen, so give a file that changes often and fast another name, as below. The `ETag` shows the size and the time of the last change to anyone who can request the file, as the `ETag` of nginx does.

`Cache-Control` is `no-cache` by default: a browser or a proxy may keep the file but asks each time, which is a cheap `304` when nothing changed. `Bond.static(app, "/assets", "public", 1_073_741_824, 300)` sets `max_age` (in seconds, 0 to a year): `public, max-age=300`. `public` lets a shared cache keep the file too, so a folder of files that only logged-in users may read keeps `max_age` at 0, or sets `Cache-Control: no-store` in an `after` filter (`Bond.header` replaces the one of the same name).

A file whose name changes with its content can be cached for a year. Pass `fingerprint: true` (the last argument) for a folder where a build tool puts a hash of the content in the name, and a name with a fingerprint is `public, max-age=31536000, immutable`: a browser keeps it and never asks again. A fingerprint is a part of 8 to 64 lowercase hex digits, with at least one letter and one digit, between the first part of the name and the extension, split by `.` or `-`: `app.3f9a1c2b.css`, `app-3f9a1c2b.css`, `main.3f9a1c2b.chunk.js`. A date (`report.20240131.pdf`) or a Unix time (`photo-1712345678.png`) has no letter, so it is not one. `fingerprint: true` is your promise that a name is new whenever its content is: a fingerprinted file that you overwrite is stale in every browser for a year, and no `ETag` helps, since an `immutable` file is not asked about. Without `fingerprint: true`, no name is treated differently.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def get(app: Bond.App, path: String, tag: String) -> HttpResponse
  headers = [Header(name: "If-None-Match", value: tag)]
  return Testing.request(app, "GET", path, headers)
end

def etag(response: HttpResponse) -> String
  return HTTP.header_values(response.headers, "etag").first
end

def main() -> Void
  Dir.mkdir("static_cache_sample").unwrap!
  File.write_text("static_cache_sample/app.css", "body {}").unwrap!
  File.write_text("static_cache_sample/app.3f9a1c2b.css", "body {}").unwrap!
  app = Bond.app() |> Bond.static("/assets", "static_cache_sample")
  versioned = Bond.app() |> Bond.static("/assets", "static_cache_sample", 1_073_741_824, 0, true)

  first = Testing.request(app, "GET", "/assets/app.css")
  puts("#{first.status} #{HTTP.header_values(first.headers, "cache-control").first}")
  puts(get(app, "/assets/app.css", etag(first)).status)
  puts(get(app, "/assets/app.css", "\"0-0\"").status)

  File.write_text("static_cache_sample/app.css", "body { margin: 0 }").unwrap!
  changed = get(app, "/assets/app.css", etag(first))
  puts("#{changed.status} #{etag(changed) != etag(first)}")

  fingerprinted = Testing.request(app, "GET", "/assets/app.3f9a1c2b.css")
  puts(HTTP.header_values(fingerprinted.headers, "cache-control").first)
  fingerprinted = Testing.request(versioned, "GET", "/assets/app.3f9a1c2b.css")
  puts(HTTP.header_values(fingerprinted.headers, "cache-control").first)
  Path.remove("static_cache_sample/app.css").unwrap!
  Path.remove("static_cache_sample/app.3f9a1c2b.css").unwrap!
  Path.remove("static_cache_sample").unwrap!
end
```

```output
200 no-cache
304
200
200 true
no-cache
public, max-age=31536000, immutable
```

## Which paths are a file

A path is the answer of a file only when it names a plain file of the folder. All the other paths are answered as a path with no route, so a [custom `not_found` handler](/guide/errors/) applies and nothing says why the file was refused:

- A file that is missing, a folder (Bond lists no folder) and any other kind of entry, such as a FIFO.
- A name that starts with a dot: `.git`, `.env` and `..` itself. The rule also applies to the real path of the file below the folder, so a link to `.env`, or into a folder such as `.git/`, is a 404 too.
- A name that Windows opens as a device (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`), with any extension and in any case.
- A way out of the folder: `..`, `%2e%2e` (a path with `%252e` is only a name with a percent sign, and a file that is not there), an encoded slash (`..%2F`), a backslash (`..%5C`), a colon, an absolute path (`%2Fetc%2Fpasswd`), a NUL or another control character, and a bad percent escape. Each segment is decoded first and then checked, so the encoded forms are refused the same as the plain ones.
- A symbolic link whose target is outside the folder. The real path of the file, with the links followed, must be inside the real path of the folder. A link to another file inside the folder is served.

There is a short time between this check and the read of the file. Do not let untrusted users create links in the folder.

## Any file, and the size

Bond sends the file with [`Bond.send_file`](/guide/files/), which reads it in pieces, so the memory does not grow with the size. The bytes are sent as they are, text or not; a text file is not checked to be UTF-8, and its `charset=utf-8` is a claim of the type, not a test of the file.

A file over `max_bytes` is a 500. A file of exactly `max_bytes` is served. The default is 1 GiB; `Bond.static(app, "/assets", "public", 65_536)` sets a smaller limit. A `max_bytes` that is 0 or over 1 TiB, and a prefix that is not a path or has a `:param`, stop the program when the app is built, like a bad route pattern. Bond has no compression, so a large file that many clients ask for belongs on a web server or a CDN in front of Bond (a `304` already saves the bytes).

A 500 for a file is a failure like the `error` of a handler: it goes to the [`on_error` handler](/guide/errors/), which gets the reason in words (`the static file app.css is over 10 bytes`), and the reason is written to stderr. The default handler answers the fixed text of every 500.

## An example

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def show(app: Bond.App, method: String, path: String) -> Void
  response = Testing.request(app, method, path)
  type = HTTP.header_values(response.headers, "content-type").join(",")
  puts("#{method} #{path} #{response.status} #{type} #{response.body.size}")
end

def main() -> Void
  Dir.mkdir("static_sample").unwrap!
  File.write_text("static_sample/hello.txt", "hello").unwrap!
  File.write_text("static_sample/app.css", "body { margin: 0 }").unwrap!
  app = Bond.app() |> Bond.static("/assets", "static_sample")
  show(app, "GET", "/assets/hello.txt")
  show(app, "GET", "/assets/app.css")
  show(app, "HEAD", "/assets/hello.txt")
  show(app, "GET", "/assets/%2e%2e/agentica.toml")
  show(app, "GET", "/assets/missing.txt")
  show(app, "POST", "/assets/hello.txt")
  Path.remove("static_sample/hello.txt").unwrap!
  Path.remove("static_sample/app.css").unwrap!
  Path.remove("static_sample").unwrap!
end
```

```output
GET /assets/hello.txt 200 text/plain; charset=utf-8 5
GET /assets/app.css 200 text/css; charset=utf-8 18
HEAD /assets/hello.txt 200 text/plain; charset=utf-8 0
GET /assets/%2e%2e/agentica.toml 404 text/plain; charset=utf-8 9
GET /assets/missing.txt 404 text/plain; charset=utf-8 9
POST /assets/hello.txt 405 text/plain; charset=utf-8 18
```
