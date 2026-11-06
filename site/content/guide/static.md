---
title: Static files
weight: 8
description: Serve the files of a folder under a path, with the type from std/mime and no way out of the folder.
---

# Static files

`Bond.static(app, "/assets", "public")` serves the files of the folder `public` under `/assets`: `/assets/img/logo.svg` is `public/img/logo.svg`. The folder is relative to the working directory of the program, or absolute (prefer absolute: a program started in another folder would not find a relative one). It must exist when the app is built, or the program stops at once, like a bad route pattern; its real path is kept from then on.

Only `GET` and `HEAD` read a file. Any other method on a path under the prefix is a 405 with `Allow: GET, HEAD`. A route of the app wins over a file. Call `Bond.static` more than once for more folders: the first prefix that holds the path decides, so a second folder under the same prefix is never read. Put the longer prefix first (`/assets/vendor` before `/assets`, or `/assets/vendor/x.js` is looked up in `public/vendor/`).

## What the answer has

The answer is built as [`Bond.send_file`](/guide/files/) builds it, so these work as described there: `Content-Type` from `std/mime` (an unknown extension, or none, is `application/octet-stream`), `X-Content-Type-Options: nosniff`, `Content-Length`, ranges (206, 416), `HEAD`, and the `ETag` and `Last-Modified` of a [conditional request](/guide/files/#conditional-requests). Bond reads no `If-Range`. What is its own is below: `Cache-Control`, the cache of small files and gzip.

## Caching

A matching `If-None-Match` or `If-Modified-Since` is a `304` that costs one `stat` and no read of the file (except a `GET` for a small file that the cache does not hold yet, which reads it once to keep it; a `HEAD` never does). The `ETag` shows the size and the time of the last change to anyone who can request the file, as the `ETag` of nginx does. A file that changes often and fast needs another name each time (see fingerprints below), since an edit that keeps the size within the same second is not seen.

`Cache-Control` is `no-cache` by default: a client may keep the file but asks each time, a cheap `304` when nothing changed. `Bond.static(app, "/assets", "public", 1_073_741_824, 300)` sets `max_age` (in seconds, 0 to a year): `public, max-age=300`. `public` lets a shared cache keep the file too, so a folder that only logged-in users may read keeps `max_age` at 0, or sets `Cache-Control: no-store` in an `after` filter.

Pass `true` as the `fingerprint` argument for a folder where a build tool puts a hash of the content in the name: a name with a fingerprint is `public, max-age=31536000, immutable`, so a browser never asks again. A fingerprint is 8 to 64 lowercase hex digits, with at least one letter and one digit, between the first part of the name and the extension, split by `.` or `-`: `app.3f9a1c2b.css`, `main.3f9a1c2b.chunk.js`. A date (`report.20240131.pdf`) or a Unix time (`photo-1712345678.png`) has no letter, so it is not one. This is your promise that a name is new whenever its content is: a fingerprinted file that you overwrite is stale in every browser for a year, and no `ETag` helps. Without it, no name is treated differently.

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

## Size limits

A file over `max_bytes` is a 500; a file of exactly `max_bytes` is served. The default is 1 GiB; `Bond.static(app, "/assets", "public", 65_536)` sets a smaller limit. A file of at most `piece_bytes` is read in one call, and a bigger one in pieces, as [`Bond.send_file`](/guide/files/) does (4 KiB to 16 MiB, 64 KiB by default): `Bond.static(app, "/assets", "public", 1_073_741_824, 0, false, 16_777_216, 262_144)` uses pieces of 256 KiB. A `max_bytes` of 0 or over 1 TiB, a `piece_bytes` or `cache_bytes` out of range, and a prefix that is not a path or has a `:param`, stop the program when the app is built.

## The cache of small files

Each folder keeps the files of at most `piece_bytes` in memory, up to `cache_bytes` in all (16 MiB by default, the `cache_bytes` argument after `fingerprint`; 0 turns the cache off). A hit costs one `stat`: the entry is used while the file has the size and the time of change it had when it was read, and an edited file is read again (an edit that keeps both within the same second is not seen). A file that is gone is a 404 at once.

A file is stored only under its real name, after all the checks of [Which paths are a file](#which-paths-are-a-file): `%62ig.css` for `big.css`, a link, or another case on a folder that ignores it is answered the long way, so no spelling of a name adds to the cache or pushes out another file. A file that would take more than half of `cache_bytes` is not kept, and when an entry does not fit the cache is emptied and starts again, so a folder with more small files than the budget holds needs a bigger `cache_bytes`.

With `fingerprint` on, a fingerprinted name is not checked against the disk at all, as part of your promise that its content never changes: a deleted or overwritten file is served from memory until the program restarts.

## Compression

Bond compresses nothing at run time: the build makes the `.gz` (`gzip -9 -k -n app.css`). A text file (the `std/mime` text types, and `image/svg+xml`) is sent gzipped when `app.css.gz` sits next to `app.css`, the client's `Accept-Encoding` lists `gzip` (not `gzip;q=0`) and it asks for the whole file. The answer has `Content-Encoding: gzip`, `Vary: Accept-Encoding` and its own `ETag` (from the `.gz`, ending in `-gz`). A text file always has the `Vary`, so a shared cache keeps the two forms apart. A `Range` request gets the file as it is. An image, a font or a `.zip` is never looked up.

The `.gz` is used only when it is a plain file with bytes, **not older than the file** (a `.gz` left behind an edit is not served), and inside the folder by the same rules as the file; otherwise, or when it cannot be read, the file as it is answers. For a small file the `.gz` is kept in the cache with it, and a hit also does a `stat` of the `.gz` path (a second one), so a `.gz` that is rewritten, removed, or added after the file (a deploy that copies the file first) makes the entry stale. A `.gz` over `max_bytes` is not served, and one over `piece_bytes`, or one that would take the entry over half of `cache_bytes`, is sent from the disk, with the file not kept.
