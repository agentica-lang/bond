---
title: Static files
weight: 6
description: Serve the files of a folder under a path, with the type from std/mime and no way out of the folder.
---

# Static files

`Bond.static(app, "/assets", "public")` serves the files of the folder `public` under the path `/assets`: `/assets/app.css` is the file `public/app.css`, and `/assets/img/logo.svg` is `public/img/logo.svg`. The folder is relative to the working directory of the program, or an absolute path, and it must exist. A program that starts in another folder gets 404 for every file, so use an absolute path when it can.

Only `GET` and `HEAD` read a file. Any other method on a path under the prefix is a 405 with `Allow: GET, HEAD`. A route of the app wins over a file: if you add `Bond.get("/assets/special.txt", ...)`, the handler answers, and the file is never read. Call `Bond.static` more than once for more folders, each with its own prefix. The first prefix that holds the path decides, so a second folder under the same prefix is never read.

## What the answer has

- `Content-Type` from `std/mime` by the extension of the file (`text/css`, `application/json`, `image/svg+xml`), and `application/octet-stream` for an extension it does not know. A text type gets `; charset=utf-8`.
- `X-Content-Type-Options: nosniff`, so a browser uses the type that Bond sent and does not guess a script from a text file.
- `Content-Length` is added by the HTTP server, as for every answer of Bond. A `HEAD` answer has the same headers, with the length of the file, and the HTTP server sends no body for it (`Testing.request` shows the body, since it has no socket).

Bond sets no cache headers: no `ETag`, no `Last-Modified`, no `Cache-Control` and no `304`. Add a `Cache-Control` with an `after` filter if you want one.

## Which paths are a file

A path is the answer of a file only when it names a plain file of the folder. All the other paths are answered as a path with no route, so a [custom `not_found` handler](/guide/errors/) applies and nothing says why the file was refused:

- A file that is missing, and a folder (Bond lists no folder).
- A name that starts with a dot: `.git`, `.env` and `..` itself.
- A way out of the folder: `..`, `%2e%2e`, an encoded slash (`..%2F`), a backslash (`..%5C`), a colon, an absolute path (`%2Fetc%2Fpasswd`), a NUL or another control character, and a bad percent escape. Each segment is decoded first and then checked, so the encoded forms are refused the same as the plain ones.
- A symbolic link whose target is outside the folder. The real path of the file, with the links followed, must be inside the real path of the folder. A link to another file inside the folder is served.

There is a short time between this check and the read of the file. Do not let untrusted users create links in the folder.

## Size and text only

`File.read_text` gives the body, and the body of an `HttpResponse` is a UTF-8 text, so Bond serves files that are UTF-8 text: HTML, CSS, JavaScript, JSON, SVG, plain text. A binary file, such as a PNG or a font, is not valid UTF-8 and is a 500. It will be served when `std/http` has bodies of bytes. Until then, serve images and fonts from a CDN or a web server in front of Bond.

A file over `max_bytes` is a 500 too. The default is 1 MiB, which is also the most `File.read_text` reads: `Bond.static(app, "/assets", "public", 65_536)` sets a smaller limit. A `max_bytes` that is 0 or over 1 MiB, and a prefix that is not a path or has a `:param`, stop the program when the app is built, like a bad route pattern. A 500 for a file has the fixed text of every 500, and the reason goes to stderr.

## An example

The sample makes a folder with two files, serves it and removes it.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def show(app: Bond.App, method: String, path: String) -> Void
  response = Testing.request(app, method, path, [], "")
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
HEAD /assets/hello.txt 200 text/plain; charset=utf-8 5
GET /assets/%2e%2e/agentica.toml 404 text/plain; charset=utf-8 9
GET /assets/missing.txt 404 text/plain; charset=utf-8 9
POST /assets/hello.txt 405 text/plain; charset=utf-8 18
```
