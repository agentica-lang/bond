## Protection against cross-site request forgery that needs no token: a browser says where a request comes from, in
## `Sec-Fetch-Site` and `Origin`, and `csrf(app)` refuses an unsafe request that comes from another site.

import Apps from "app"
import Conns from "conn"
import {App} from "app"
import {Conn} from "conn"

# The methods that must not change anything (RFC 9110 section 9.2.1, minus TRACE, which Bond does not route).
SAFE_METHODS = ["GET", "HEAD", "OPTIONS"]

## Adds a `before` filter that answers 403 to a `POST`, `PUT`, `PATCH` or `DELETE` (any method that is not `GET`,
## `HEAD` or `OPTIONS`) that a page of another site sent, so a form on `evil.test` cannot act for a visitor of your
## site. The rule is the one of Go's `http.CrossOriginProtection`:
##
## 1. A request whose `Origin` is one of `allowed_origins` passes.
## 2. With a `Sec-Fetch-Site` header (every current browser sends it): `same-origin` and `none` (the visitor typed the
##    address or used a bookmark) pass, and `same-site` (another subdomain) and `cross-site` are refused.
## 3. With no `Sec-Fetch-Site` but an `Origin`: it passes when the host of the origin is the `Host` of the request, and
##    it is refused otherwise (so is `Origin: null`).
## 4. With neither: it passes. A browser sends at least one of them for a request that can carry a cookie, so this is a
##    tool such as `curl` or a server, which a forged form cannot be.
##
## `allowed_origins` are origins as a browser writes them (`"https://admin.example.com"`: scheme, host and a port when
## it is not the default, no path), for another site that may call the app. The program stops when one is not. The
## scheme of a request is not checked against `Host` (the server may sit behind a proxy that ends TLS).
##
## This replaces tokens in forms, but it only protects what a browser sends: `GET` must stay free of side effects.
## Filters run in the order they were added, so add it before any filter that does work for a request.
export def csrf(app: App, allowed_origins: List[String] = []) -> App
  origins = allowed_origins.map do |origin| origin.downcase end
  for origin in origins
    if not origin_shape?(origin)
      bad: Result[App] = error("bond: #{origin} is not an origin like https://example.com")
      return bad.unwrap!
    end
  end

  return Apps.before(app) do |conn| check(origins, conn) end
end

# `scheme://host` or `scheme://host:port`, with nothing after the host.
def origin_shape?(origin: String) -> Bool
  parts = origin.split("://")
  if parts.size != 2
    return false
  end

  return (parts[0] == "http" or parts[0] == "https") and parts[1] != "" and not parts[1].include?("/")
end

def check(origins: List[String], conn: Conn) -> Result[Conn]
  if same_origin?(origins, conn)
    return ok(conn)
  end

  return ok(Conns.halt(conn, 403, "cross-origin request refused"))
end

def same_origin?(origins: List[String], conn: Conn) -> Bool
  if SAFE_METHODS.any? do |method| method == conn.method end
    return true
  end

  origin = Conns.request_header(conn, "origin").unwrap_or("").downcase
  if origins.any? do |allowed| allowed == origin end
    return true
  end

  site = Conns.request_header(conn, "sec-fetch-site").unwrap_or("").downcase
  if site != ""
    return site == "same-origin" or site == "none"
  end

  if origin == ""
    return true
  end

  host = Conns.request_header(conn, "host").unwrap_or("").downcase
  parts = origin.split("://")
  return host != "" and parts.size == 2 and parts[1] == host
end
