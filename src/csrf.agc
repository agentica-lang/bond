## Protection against cross-site request forgery that needs no token: a browser says where a request comes from, in
## `Sec-Fetch-Site` and `Origin`, and `csrf(app)` refuses an unsafe request that comes from another site.

import Apps from "app"
import Conns from "conn"
import {App} from "app"
import {Conn} from "conn"

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
## A request with two `Origin` headers, or two `Sec-Fetch-Site` headers, is refused: a browser sends one of each.
##
## `allowed_origins` are origins as a browser writes them (`"https://admin.example.com"`: scheme, host and a port when
## it is not the default, no path), for another site that may call the app. The program stops when one is not, and
## when it has the default port (`https://example.com:443` never matches: a browser leaves that port out). The scheme
## of a request is not checked against `Host` (the server may sit behind a proxy that ends TLS), so an `http://` Origin
## for the host of the request passes.
##
## This replaces tokens in forms, but it only protects what a browser sends: `GET` must stay free of side effects.
## Filters run in the order they were added, so add it before any filter that does work for a request.
def csrf(app: App, allowed_origins: List[String] = []) -> App
  origins = checked_origins(allowed_origins)
  Apps.before(app) do |conn| check(origins, conn) end
end

## The allowed origins of `csrf` and `Bond.websocket` in lowercase, as a browser writes them. The program stops when
## one can never be the `Origin` of a browser (see `csrf`), since that is a mistake of the program.
def checked_origins(allowed_origins: List[String]) -> List[String]
  origins = allowed_origins.map do |origin| origin.downcase end
  for origin in origins
    problem = origin_problem(origin)
    if problem != ""
      bad: Result[List[String]] = error("bond: the allowed origin #{origin} #{problem}")
      return bad.unwrap!
    end
  end

  origins
end

## True when `origin` (in lowercase) names the host of the request: its part after `://` is the `Host` header. The
## scheme is not compared, since the server may sit behind a proxy that ends TLS.
def host_origin?(origin: String, conn: Conn) -> Bool
  host = Conns.request_header(conn, "host").unwrap_or("").downcase
  parts = origin.split("://")
  host != "" and parts.size == 2 and parts[1] == host
end

## True when the request has more than one header `name` (in lowercase), which a browser never sends for `Origin`.
def repeated?(conn: Conn, name: String) -> Bool
  same = conn.headers.select do |field| field.name.downcase == name end
  same.size > 1
end

private

# The methods that must not change anything (RFC 9110 section 9.2.1, minus TRACE, which Bond does not route).
SAFE_METHODS = ["GET", "HEAD", "OPTIONS"]

DIGITS = Set.new(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])

# Why `origin` can never be the `Origin` header of a browser, or "" when it can: it is `scheme://host` or
# `scheme://host:port` with nothing else (a browser leaves the port out when it is the default of the scheme).
def origin_problem(origin: String) -> String
  parts = origin.split("://")
  if parts.size != 2 or (parts[0] != "http" and parts[0] != "https")
    return "must start with http:// or https:// (like https://example.com)"
  end

  rest = parts[1]
  if rest.split("").any? do |ch| ch == "/" or ch == "?" or ch == "#" or ch == "@" or ch == "\\" or ch == " " end
    return "must be only a scheme, a host and a port: no path, query, fragment or user"
  end

  host = rest
  port = ""
  if rest.start_with?("[")
    close = rest.index_of("]").unwrap_or(-1)
    host = rest.slice(0, close + 1)
    after = rest.slice(close + 1, rest.length - close - 1)
    return "has a bad IPv6 host" if close < 0 or (after != "" and not after.start_with?(":"))

    if after != ""
      port = after.slice(1, after.length - 1)
    end
  else
    pieces = rest.split(":")
    host = pieces[0]
    return "has more than one port" if pieces.size > 2

    if pieces.size == 2
      port = pieces[1]
    end
  end

  return "has no host" if host == "" or host == "[]"

  if rest.end_with?(":") or (port != "" and not port.split("").all? do |ch| DIGITS.include?(ch) end)
    return "has a port that is not a number"
  end

  return "has a port out of 1 to 65535" if port != "" and (port.length > 5 or port.to_i! < 1 or port.to_i! > 65535)

  if (parts[0] == "https" and port == "443") or (parts[0] == "http" and port == "80")
    return "has the default port of its scheme, which a browser leaves out of the Origin: write it with no port"
  end

  ""
end

def check(origins: List[String], conn: Conn) -> Result[Conn]
  return ok(conn) if same_origin?(origins, conn)

  ok(Conns.halt(conn, 403, "cross-origin request refused"))
end

def same_origin?(origins: List[String], conn: Conn) -> Bool
  return true if SAFE_METHODS.any? do |method| method == conn.method end

  # A browser sends each of these once. A request with two is not from a browser, and `request_header` would judge it
  # by the first only, so it is refused.
  return false if repeated?(conn, "origin") or repeated?(conn, "sec-fetch-site")

  origin = Conns.request_header(conn, "origin").unwrap_or("").downcase
  return true if origins.any? do |allowed| allowed == origin end

  site = Conns.request_header(conn, "sec-fetch-site").unwrap_or("").downcase
  return site == "same-origin" or site == "none" if site != ""

  return true if origin == ""

  host_origin?(origin, conn)
end
