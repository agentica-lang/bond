---
title: Cross-site requests
weight: 7
description: Refuse a POST that a page of another site sent, with no token in the forms.
---

# Cross-site requests

A page on `evil.test` can make a visitor's browser send a `POST` to your site with the cookies of your site: a cross-site request forgery. `Bond.csrf(app)` stops it with the headers that browsers add to say where a request comes from, so a form needs no token.

`Bond.csrf` adds a `before` filter. A request with a method other than `GET`, `HEAD` and `OPTIONS` (so `POST`, `PUT`, `PATCH` and `DELETE`) is judged by these rules, in order:

1. Its `Origin` is one of the `allowed_origins` you gave: it passes.
2. It has a `Sec-Fetch-Site` header, which every current browser sends: `same-origin` and `none` (the visitor typed the address, or used a bookmark) pass. `same-site` (another subdomain of the site) and `cross-site` are refused.
3. It has no `Sec-Fetch-Site` but has an `Origin`: it passes when the host of the origin, with its port, is the `Host` of the request. `Origin: null` is refused.
4. It has neither: it passes. A browser sends one of them with a request that can carry a cookie, so this is a program such as `curl` or another server, and a forged form cannot be one.

A request with two `Origin` headers, or two `Sec-Fetch-Site` headers, is refused too: a browser sends one of each.

A refused request is a halted `403` with the text `cross-origin request refused`; the `after` filters still run for it, as for any halted answer. A `GET` is never refused, so a `GET` that changes something is not protected: keep the changes in `POST` and the other unsafe methods.

The scheme of the origin is not compared, since the server may sit behind a proxy that ends TLS: an `http://` Origin for the same host and port passes, even if the app is served over `https://`. The proxy must pass the `Host` header on, or rule 3 refuses a browser that sends no `Sec-Fetch-Site`.

## Allowing another site

`allowed_origins` lists the sites that may call your app on purpose, for example a front end on another domain. An origin is written as a browser writes it: `"https://admin.example.com"`, with a port when it is not the default, and no path. The comparison ignores case. The program stops at the call when an entry could never be the `Origin` of a browser: a path, a query, a fragment or a user (`/`, `?`, `#`, `@`), no host, a port that is not 1 to 65535, a scheme that is not `http` or `https`, or the default port of the scheme (`https://example.com:443`), which a browser leaves out of the header: write `https://example.com`.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def transfer(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "transferred"))
end

def try_post(app: Bond.App, origin: String, site: String) -> Int
  headers = [
    Header(name: "Host", value: "example.com"),
    Header(name: "Origin", value: origin),
    Header(name: "Sec-Fetch-Site", value: site),
  ]
  return Testing.request(app, "POST", "/transfer", headers).status
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.csrf(["https://admin.example.net"])
    |> Bond.post("/transfer", &transfer)
  )
  puts(try_post(app, "https://example.com", "same-origin"))
  puts(try_post(app, "https://evil.test", "cross-site"))
  puts(try_post(app, "https://admin.example.net", "cross-site"))
  puts(Testing.request(app, "POST", "/transfer").status)
end
```

```output
200
403
200
200
```

The last line is a request with no `Origin` and no `Sec-Fetch-Site`, as `curl` sends it. In a test, send the headers yourself, as above, to see how a browser is treated.

This check does not replace `SameSite=Lax` on the session cookie (which [Sessions](../sessions/) sets by default); use both.
