---
title: Static files
weight: 6
description: Serve the files of a folder under a path, with the type from std/mime and no way out of the folder.
---

# Static files

`Bond.static(app, "/assets", "public")` serves the files of the folder `public` under the path `/assets`: `/assets/app.css` is the file `public/app.css`, and `/assets/img/logo.svg` is `public/img/logo.svg`. The folder is relative to the working directory of the program, or an absolute path. It must be a folder that exists when the app is built: if not, the program stops at once, like a bad route pattern, and the real path of the folder is kept from then on. A program that starts in another folder would not find a relative one, so use an absolute path when it can.

Only `GET` and `HEAD` read a file. Any other method on a path under the prefix is a 405 with `Allow: GET, HEAD`. A route of the app wins over a file: if you add `Bond.get("/assets/special.txt", ...)`, the handler answers, and the file is never read. Call `Bond.static` more than once for more folders, each with its own prefix. The first prefix that holds the path decides, so a second folder under the same prefix is never read. Put the longer prefix first: `Bond.static("/assets/vendor", "vendor")` before `Bond.static("/assets", "public")`, or `/assets/vendor/x.js` is looked up in `public/vendor/`.

## What the answer has

- `Content-Type` from `std/mime` by the extension of the file (`text/css`, `application/json`, `image/png`), with `; charset=utf-8` added for a text type (`MIME.text?`). A file with an extension that `std/mime` does not know, or with none (`LICENSE`), is `application/octet-stream`.
- `X-Content-Type-Options: nosniff`, so a browser uses the type that Bond sent and does not guess a script from a text file.
- `Content-Length` is added by the HTTP server, as for every answer of Bond. A `HEAD` answer has the same headers, with the length of the file, and the HTTP server sends no body for it (`Testing.request` shows the body, since it has no socket).

Bond sets no cache headers: no `ETag`, no `Last-Modified`, no `Cache-Control` and no `304`. Add a `Cache-Control` with an `after` filter if you want one.

## Which paths are a file

A path is the answer of a file only when it names a plain file of the folder. All the other paths are answered as a path with no route, so a [custom `not_found` handler](/guide/errors/) applies and nothing says why the file was refused:

- A file that is missing, and a folder (Bond lists no folder).
- A name that starts with a dot: `.git`, `.env` and `..` itself. The rule also applies to the real path of the file below the folder, so a link to `.env`, or into a folder such as `.git/`, is a 404 too.
- A name that Windows opens as a device (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`), with any extension and in any case.
- A way out of the folder: `..`, `%2e%2e` (a path with `%252e` is only a name with a percent sign, and a file that is not there), an encoded slash (`..%2F`), a backslash (`..%5C`), a colon, an absolute path (`%2Fetc%2Fpasswd`), a NUL or another control character, and a bad percent escape. Each segment is decoded first and then checked, so the encoded forms are refused the same as the plain ones.
- A symbolic link whose target is outside the folder. The real path of the file, with the links followed, must be inside the real path of the folder. A link to another file inside the folder is served.

There is a short time between this check and the read of the file. Do not let untrusted users create links in the folder.

## Any file, and the size

Bond reads the file with `File.read_bytes` and sends the bytes as they are: HTML, CSS, JavaScript, JSON and SVG, and also images, fonts, archives and PDFs. A text file is not checked to be UTF-8, and its `charset=utf-8` is a claim of the type, not a test of the file.

A file over `max_bytes` is a 500. A file of exactly `max_bytes` is served. The default is 1 MiB, which is also the most one `File.read_bytes` call reads: `Bond.static(app, "/assets", "public", 65_536)` sets a smaller limit. A `max_bytes` that is 0 or over 1 MiB, and a prefix that is not a path or has a `:param`, stop the program when the app is built, like a bad route pattern. A larger file, such as a video, belongs on a web server or a CDN in front of Bond.

A 500 for a file is a failure like the `error` of a handler: it goes to the [`on_error` handler](/guide/errors/), which gets the reason in words (`the static file app.css is over 10 bytes`), and the reason is written to stderr. The default handler answers the fixed text of every 500.

Only regular files are served (a folder and other kinds of entry are a 404). `File.stat` cannot tell a FIFO from a file ([Agentica issue #811](https://github.com/agentica-lang/agentica/issues/811)), so a FIFO in the folder is not refused; the read gives up after five seconds with a 500. Do not put one there.

## An example

The sample makes a folder with two files, serves it and removes it.

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
  File.write_text("static_sample/logo.png", "x").unwrap!
  app = Bond.app() |> Bond.static("/assets", "static_sample")
  show(app, "GET", "/assets/hello.txt")
  show(app, "GET", "/assets/app.css")
  show(app, "GET", "/assets/logo.png")
  show(app, "HEAD", "/assets/hello.txt")
  show(app, "GET", "/assets/%2e%2e/agentica.toml")
  show(app, "GET", "/assets/missing.txt")
  show(app, "POST", "/assets/hello.txt")
  Path.remove("static_sample/hello.txt").unwrap!
  Path.remove("static_sample/app.css").unwrap!
  Path.remove("static_sample/logo.png").unwrap!
  Path.remove("static_sample").unwrap!
end
```

```output
GET /assets/hello.txt 200 text/plain; charset=utf-8 5
GET /assets/app.css 200 text/css; charset=utf-8 18
GET /assets/logo.png 200 image/png 1
HEAD /assets/hello.txt 200 text/plain; charset=utf-8 5
GET /assets/%2e%2e/agentica.toml 404 text/plain; charset=utf-8 9
GET /assets/missing.txt 404 text/plain; charset=utf-8 9
POST /assets/hello.txt 405 text/plain; charset=utf-8 18
```
