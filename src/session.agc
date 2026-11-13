## Sessions kept in a signed cookie: the data of a visitor lives in the browser, and Bond signs it with HMAC-SHA256
## so that a changed cookie is not trusted. `sessions(app, options)` adds the two filters that load the session of a
## request and write it back; a handler reads and changes it with `session`, `get_session`, `set_session`,
## `delete_session` and `clear_session`.

import C from "std/cookie"
import Apps from "app"
import Cookies from "cookies"
import {App} from "app"
import {Conn} from "conn"

## How a session cookie is signed and sent. `secret` signs the cookie and must have at least 32 bytes (draw it from
## `OpenSSL.Random.hex(32)` once and keep it out of the source). `old_secrets` are the secrets that signed cookies
## before: a cookie with one of them is read, and written again with `secret` and a new `max_age` from that moment (so
## a session that is in use outlives the rotation), so a secret is rotated by putting the new one in `secret` and the
## old one in `old_secrets` until the last cookie that it signed has expired. `name` is the
## cookie, `max_age` its life in seconds (the signed cookie holds the date too, so a client that keeps an old cookie
## does not get a longer session), `secure` adds `Secure` (set it in production, over HTTPS), `same_site` is `Strict`,
## `Lax` (the default: not sent with a cross-site `POST`) or `None` (which needs `secure`). The cookie is always
## `HttpOnly`. `path` and `domain` are those of the cookie. In production use `name: "__Host-session"` with
## `secure: true` (and the default `path` and no `domain`): a browser then refuses a cookie of that name from a sibling
## subdomain, which could otherwise plant a cookie that is signed, but is its own.
struct SessionOptions
  secret: String
  old_secrets: List[String] = []
  name: String = "_bond_session"
  max_age: Int = 1_209_600
  secure: Bool = false
  same_site: String = "Lax"
  path: String = "/"
  domain: String = ""
end

## Adds the filters of the sessions to `app`: a `before` filter that reads the cookie, and an `after` filter that
## writes it when a handler changed the session. A cookie that is missing, that is not signed with `secret` or one of
## the `old_secrets`, that was changed, or that has expired, is an empty session (it is never an error of the
## client). Nothing is sent when the session did not change. The program stops when the options are wrong: a secret of
## less than 32 bytes, an empty name or path, a `max_age` below 1 or a `same_site` that is not `Strict`, `Lax` or
## `None` (`None` also needs `secure`). Call it once, before the routes that use the session or after them: the filters
## run for every route.
##
## The cookie is signed, not encrypted: anyone who has it can read what it holds, so keep there an id, never a
## secret. A `Set-Cookie` that is over 3800 bytes is a failure of the answer (a 500 through the error handler), since a
## browser drops a bigger cookie.
def sessions(app: App, options: SessionOptions) -> App
  problem = check(options)
  if problem != ""
    bad: Result[App] = error("bond: #{problem}")
    return bad.unwrap!
  end

  loading = Apps.before(app) do |conn| load(options, conn) end
  Apps.after(loading) do |conn| save(options, conn) end
end

## The session of the request: a map from name to value, empty for a visitor with no valid session (and when
## `sessions` was not called). It holds what the handlers of this request set so far.
def session(conn: Conn) -> Map[String, String] = conn.session

## One value of the session, or an `error` when it is not there. A missing value is not a mistake of the client, so it
## is a plain `error`, like `cookie`: use `unwrap_or` or `case`.
def get_session(conn: Conn, name: String) -> Result[String]
  case conn.session.get(name)
    some(value) -> ok(value)
    none -> error("no session value #{name}")
  end
end

## A `Conn` whose session has `name` set to `value`; the answer carries the new session in its cookie. The session is
## text only: encode a number or a list (`to_s`, `JSON.encode`) before, and decode it after.
def set_session(conn: Conn, name: String, value: String) -> Conn
  conn.with(session: conn.session.put(name, value), session_changed: true)
end

## A `Conn` whose session no longer has `name`. When it was not there, the `Conn` is the same.
def delete_session(conn: Conn, name: String) -> Conn
  return conn if not conn.session.key?(name)

  conn.with(session: conn.session.delete(name), session_changed: true)
end

## A `Conn` with an empty session: the answer deletes the cookie. Call it at logout, and before you set the user at
## login, so that nothing of a session the visitor had before is kept.
def clear_session(conn: Conn) -> Conn = conn.with(session: {}, session_changed: true)

## The value of the session cookie for `data`, signed with `options.secret` and valid for `options.max_age` seconds
## from now: what `sessions` would send. `Testing.session_cookie` uses it to make the `Cookie` header of a request
## that has a session. It does not check the options (a short secret or a negative `max_age` are accepted, which is how
## a test makes an expired cookie). An `error` when the value would be over the size of a cookie.
def seal(options: SessionOptions, data: Map[String, String]) -> Result[String]
  envelope = Envelope(exp: Time.now_ms() + options.max_age * 1000, data: data)
  payload = Base64.urlsafe_encode64(Envelope.codec.encode(envelope).bytes, false)
  mac = Base64.urlsafe_encode64(signature(options.secret, options.name, payload), false)
  value = "#{payload}.#{mac}"
  if options.name.length + value.length > MAX_COOKIE_BYTES
    return error("bond: the session cookie has #{value.length} bytes, more than #{MAX_COOKIE_BYTES}")
  end

  ok(value)
end

private

# The shortest secret: 32 bytes, the size of the SHA-256 digest that signs with it.
MIN_SECRET_BYTES = 32

# The most bytes of a session cookie (its name and its value). Browsers keep 4096 bytes for a cookie with its
# attributes, and a cookie that is over the limit is dropped without a word.
MAX_COOKIE_BYTES = 3800

SAME_SITE_VALUES = ["Strict", "Lax", "None"]

# What the cookie holds: the end of the session in milliseconds, and the data.
struct Envelope
  exp: Int
  data: Map[String, String]
end

# A session read from a cookie, and the place of the secret that signed it in `keys` (0 is the current one).
struct Opened
  data: Map[String, String]
  key: Int
end

def check(options: SessionOptions) -> String
  secrets = [options.secret].concat(options.old_secrets)
  if secrets.any? do |secret| secret.bytes.size < MIN_SECRET_BYTES end
    return "a session secret must have at least #{MIN_SECRET_BYTES} bytes"
  end

  return "the session cookie needs a name and a path" if options.name == "" or options.path == ""

  return "the max_age of the session must be at least 1 second" if options.max_age < 1

  if not SAME_SITE_VALUES.any? do |value| value == options.same_site end
    return "the same_site of the session must be Strict, Lax or None"
  end

  return "a session cookie with SameSite=None needs secure" if options.same_site == "None" and not options.secure

  ""
end

# The signature covers the name of the cookie too, so a value copied from another cookie of the app is not accepted.
def signature(secret: String, name: String, payload: String) -> Bytes
  OpenSSL.HMAC.sha256(secret.bytes, "#{name}.#{payload}".bytes)
end

def load(options: SessionOptions, conn: Conn) -> Result[Conn]
  case Cookies.cookies(conn).get(options.name)
    some(value) ->
      case unseal(options, value)
        ok(opened) ->
          # A cookie that an old secret signed is written again with the current one.
          ok(conn.with(session: opened.data, session_changed: opened.key > 0 and not opened.data.empty?))
        error(_) -> ok(conn)
      end

    none -> ok(conn)
  end
end

# Checks the signature against every secret, so the time does not tell which one matched, and then the end date.
def unseal(options: SessionOptions, text: String) -> Result[Opened]
  # No cookie of Bond is this long, so a bigger one is not worth a MAC for each secret.
  return error("the session cookie is too big") if text.length > MAX_COOKIE_BYTES

  parts = text.split(".")
  return error("malformed session cookie") if parts.size != 2

  mac = try Base64.urlsafe_decode64(parts[1])
  secrets = [options.secret].concat(options.old_secrets)
  found = -1
  for at in 0...secrets.size
    if OpenSSL.HMAC.secure_compare(signature(secrets[at], options.name, parts[0]), mac) and found < 0
      found = at
    end
  end

  return error("the session cookie is not signed with a known secret") if found < 0

  raw = try Base64.urlsafe_decode64(parts[0])
  envelope = try Envelope.codec.decode(try String.from_bytes(raw))
  return error("the session has expired") if envelope.exp <= Time.now_ms()

  ok(Opened(data: envelope.data, key: found))
end

def save(options: SessionOptions, conn: Conn) -> Result[Conn]
  return ok(conn) if not conn.session_changed

  return Cookies.delete_cookie(conn, options.name, options.path, options.domain) if conn.session.empty?

  value = try seal(options, conn.session)
  cookie = C.Cookie(
    name: options.name,
    value: value,
    path: options.path,
    domain: options.domain,
    max_age: options.max_age,
    secure: options.secure,
    http_only: true,
    same_site: options.same_site,
  )

  Cookies.set_cookie_with(conn, cookie)
end
