---
title: Static files
weight: 8
description: Serve the files of a folder under a path, with the type from std/mime and no way out of the folder.
---

# Static files

`Bond.static(app, "/assets", "public")` serves the files of the folder `public` under `/assets`: `/assets/img/logo.svg` is `public/img/logo.svg`. The folder is relative to the working directory of the program, or absolute (prefer absolute: a program started in another folder would not find a relative one). It must exist when the app is built, or the program stops at once, like a bad route pattern; its real path is kept from then on.

Only `GET` and `HEAD` read a file. Any other method on a path under the prefix is a 405 with `Allow: GET, HEAD`. A route of the app wins over a file. Call `Bond.static` more than once for more folders: the first prefix that holds the path decides, so a second folder under the same prefix is never read. Put the longer prefix first (`/assets/vendor` before `/assets`, or `/assets/vendor/x.js` is looked up in `public/vendor/`).

## What the answer has

- `Content-Type` from `std/mime` by the extension of the file, with `; charset=utf-8` added for a text type. An unknown extension, or none (`LICENSE`), is `application/octet-stream`.
- `X-Content-Type-Options: nosniff`, so a browser does not guess a script from a text file.
- `Content-Length` (added by the server); a `HEAD` answer has the same headers and no body.
- `Accept-Ranges: bytes` and ranges (206, 416), as for [`Bond.send_file`](/guide/files/), which sends every file.
- `ETag`, `Last-Modified` and `Cache-Control` (below). Bond reads no `If-Range`.

## Caching

Every file has an `ETag` made from its size and the time of its last change in seconds, so Bond does not read the file to make it, and a `Last-Modified` with that time. A `GET` or `HEAD` whose `If-None-Match` lists the tag (or is `*`; a `W/` prefix is ignored) is a `304 Not Modified` with the `ETag`, `Last-Modified` and `Cache-Control`, no body, and the file is not opened. Without an `If-None-Match`, an `If-Modified-Since` that is not before the time of the change is a `304` too (`If-None-Match` wins when both are sent, as RFC 9110 says; a date that is not in the form `Sun, 06 Nov 1994 08:49:37 GMT` is ignored). An edit that keeps the size within the same second is not seen, so give a file that changes often and fast another name (see fingerprints below). The `ETag` shows the size and the time of the last change to anyone who can request the file, as the `ETag` of nginx does.

`Cache-Control` is `no-cache` by default: a client may keep the file but asks each time, a cheap `304` when nothing changed. `Bond.static(app, "/assets", "public", 1_073_741_824, 300)` sets `max_age` (in seconds, 0 to a year): `public, max-age=300`. `public` lets a shared cache keep the file too, so a folder that only logged-in users may read keeps `max_age` at 0, or sets `Cache-Control: no-store` in an `after` filter.

Pass `fingerprint: true` (the last argument) for a folder where a build tool puts a hash of the content in the name: a name with a fingerprint is `public, max-age=31536000, immutable`, so a browser never asks again. A fingerprint is 8 to 64 lowercase hex digits, with at least one letter and one digit, between the first part of the name and the extension, split by `.` or `-`: `app.3f9a1c2b.css`, `app-3f9a1c2b.css`, `main.3f9a1c2b.chunk.js`. A date (`report.20240131.pdf`) or a Unix time (`photo-1712345678.png`) has no letter, so it is not one. `fingerprint: true` is your promise that a name is new whenever its content is: a fingerprinted file that you overwrite is stale in every browser for a year, and no `ETag` helps. Without it, no name is treated differently.

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

A path is the answer of a file only when it names a plain file of the folder. All other paths are answered as a path with no route, so a [custom `not_found` handler](/guide/errors/) applies and nothing says why:

- A file that is missing, a folder (Bond lists no folder) and any other kind of entry, such as a FIFO.
- A name that starts with a dot (`.git`, `.env`, `..`), also in the real path of the file below the folder: a link to `.env`, or into `.git/`, is a 404 too.
- A name that Windows opens as a device (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`), with any extension and in any case.
- A way out of the folder: `..`, `%2e%2e`, an encoded slash (`..%2F`), a backslash (`..%5C`), a colon, an absolute path (`%2Fetc%2Fpasswd`), a NUL or another control character, and a bad percent escape. Each segment is decoded once, then checked (`%252e` is only a name with a percent sign).
- A symbolic link whose real path is outside the real path of the folder. A link to another file inside the folder is served.

There is a short time between this check and the read of the file. Do not let untrusted users create links in the folder.

## Any file, and the size

A file of at most `piece_bytes` (64 KiB by default) is read in one call and answered whole. A bigger file is read in pieces of that size by a task while the server sends them, as [`Bond.send_file`](/guide/files/) does, so the memory does not grow with the size. `piece_bytes` is 4 KiB to 16 MiB: `Bond.static(app, "/assets", "public", 1_073_741_824, 0, false, 16_777_216, 262_144)` reads in pieces of 256 KiB, and a file of that size or less at once. The bytes go as they are, whatever the piece size: a text file is not checked to be UTF-8.

A file over `max_bytes` is a 500; a file of exactly `max_bytes` is served. The default is 1 GiB; `Bond.static(app, "/assets", "public", 65_536)` sets a smaller limit. A `max_bytes` of 0 or over 1 TiB, a `piece_bytes` outside its range, and a prefix that is not a path or has a `:param`, stop the program when the app is built.

## The cache of small files

Each folder keeps the files of at most `piece_bytes` in memory, up to `cache_bytes` in all (16 MiB by default; the sixth argument; 0 turns the cache off). A hit costs one `stat` of the file and no read: the entry is used when the file still has the size and the time of change it had when it was read, and an edited file is read again. As with the `ETag`, an edit that keeps the size within the same second is not seen. The entry is looked up by the path as the client wrote it, and only a path that passed all the checks of [Which paths are a file](#which-paths-are-a-file) has one; a link that is changed to point at another file is noticed when the size or the time of the new target differs. A file that is gone is a 404 at once. With `fingerprint: true`, the entry of a fingerprinted name is not checked against the disk at all (no `stat`): that name is your promise that its content never changes, so a hit costs no call to the disk, and a deleted or overwritten file is served from memory until the program restarts.

The budget counts the bytes of each entry and about 512 bytes more. A file that would take more than half of it is not kept. When an entry does not fit, the cache is emptied and starts again; the count is approximate when many requests miss at once, and errs towards emptying early. A folder that is built from a deploy and has more small files than the budget holds is better served by a bigger `cache_bytes`.

## Compression

Bond sends a text file gzipped to a client whose `Accept-Encoding` lists `gzip` (not `gzip;q=0`) and that asks for the whole file, with `Content-Encoding: gzip`, `Vary: Accept-Encoding` and its own `ETag` (the tag of the file with `-gz` at the end). It uses:

- the `.gz` file next to the file (`app.css.gz` for `app.css`), when there is one that is not older than the file, for a file of any size. Make it in the build (`gzip -9 -k -n app.css`): it costs nothing at run time.
- otherwise, for a small text file of 256 bytes to 1 MiB that the cache keeps, the bytes compressed once and kept in the cache with the file. A file that does not get smaller is sent as it is. With `cache_bytes: 0` there is no compression of this kind.

Only a text type is compressed (the types of `std/mime` that are text, `image/svg+xml` too): an image, a font or a `.zip` is already compressed. A text file always has `Vary: Accept-Encoding`, so a shared cache keeps the two forms apart. A `Range` request gets the file as it is, since a part of the compressed bytes is not a part of the file. The `.gz` file is read when the entry is made (or on each request for a file that is not kept), so a file and its `.gz` that are changed together are seen together, and a cached entry notices a new `.gz` when the file itself changes.

A 500 for a file goes to the [`on_error` handler](/guide/errors/) with the reason (`the static file app.css is over 10 bytes`), which is also written to stderr. The default handler answers the fixed text of every 500.
