## The steps of the features. A scenario drives the app of `fixtures/app.agc` in process through `Testing.request`
## (no socket), except the steps of the server, which talk to the program of `fixtures/server.agc` (or
## `fixtures/websocket_server.agc`) over a socket.

import BDD from "std/bdd"
import HTTP from "std/http"
import Bond from "../bond"
import Fixture from "fixtures/app"
import Testing from "../testing"

APP = "app"
REPLY = "reply"
PORT = "port"
SOCKET_MS = 5_000
PRODUCERS = 16
PRODUCER_MS = 5_000
PATTERN = 251
WEBSOCKET = "websocket"
# The key of RFC 6455 section 1.3, whose `Sec-WebSocket-Accept` is known.
WEBSOCKET_KEY = "dGhlIHNhbXBsZSBub25jZQ=="
TEXT_FRAME = 1
CLOSE_FRAME = 8
FINAL_BIT = 128
MASK_BIT = 128
LENGTH_BITS = 127
SHORT_LENGTH = 125
TWO_BYTE_LENGTH = 126
BYTE = 256
NORMAL_CLOSE = 1000
MASK = [55, 250, 33, 61]

struct Ask
  method: String
  path: String
  headers: List[Header]
  body: String
  raw: List[Int] = [] # the body as bytes when it is not empty (then `body` is not used)
  max_pieces: Int = 0
  timeout_ms: Int = 10_000 # keep in sync with the defaults of Testing.request
end

# What a WebSocket of a step heard after its handshake: the text of the answer to its message ("" when none came) and
# the code of the close frame of the server (0 when there was no upgrade).
struct Heard
  answer: String
  close_code: Int
end

# A frame of a WebSocket: its opcode and its payload, unmasked.
struct Frame
  opcode: Int
  payload: Bytes
end

struct Reply
  status: Int
  headers: Map[String, String]
  fields: List[Header]
  body: String # the text of the body, or "" when it is not UTF-8
  bytes: String # the byte values of the body, as "255 254 0"
end

def main() -> Void
  BDD.run([
    BDD.step("the todo app", &keep_app),
    BDD.step("the todo app with custom handlers", &keep_custom_app),
    BDD.step("the sessions app", &keep_sessions_app),
    BDD.step("the sessions app after the secret was rotated", &keep_rotated_sessions_app),
    BDD.step("the app with CSRF protection", &keep_csrf_app),
    BDD.step("the app with CSRF protection that allows https://admin.example.net", &keep_allowing_csrf_app),
    BDD.step("the app with a file of {int} bytes", &keep_big_app),
    BDD.step("the app with a folder of links", &keep_links_app),
    BDD.step("I send {string} to {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: ""))
    end,
    BDD.step("I send {string} to {string} keeping at most {int} pieces") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: "", max_pieces: args[2].to_i!))
    end,
    BDD.step("I send {string} to {string} waiting at most {int} ms") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: "", timeout_ms: args[2].to_i!))
    end,
    BDD.step("I send {string} to {string} with the body {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: args[2]))
    end,
    BDD.step("I post the bytes {string} to {string} as {string}", &post_bytes),
    BDD.step("I send {string} to {string} with the header {string} set to {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: args[2], value: args[3])], body: ""))
    end,
    BDD.step(
      "I send {string} to {string} with the header {string} set to {string} and the body:",
      &send_header_and_body,
    ),
    BDD.step(
      "I send {string} to {string} with the content types {string} and {string} and the body:",
      &send_two_types,
    ),
    BDD.step("I post to {string} as {string}:", &post_as),
    BDD.step("I post to {string} as {string} and {string}:", &post_as_two_types),
    BDD.step("I send {string} to {string} with the cookie {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: args[2])], body: ""))
    end,
    BDD.step("I send {string} to {string} with the cookies {string} and {string}", &send_two_cookies),
    BDD.step("I send {string} to {string} with the session cookie of the last answer", &send_with_last_session),
    BDD.step(
      "I send {string} to {string} with the session cookie of the last answer changed",
      &send_with_changed_session,
    ),
    BDD.step(
      "I send {string} to {string} with a session signed with the first secret for the user {string}",
      &send_with_first_secret,
    ),
    BDD.step(
      "I send {string} to {string} with a session signed for another cookie name for the user {string}",
      &send_with_other_name,
    ),
    BDD.step("I send {string} to {string} with an expired session for the user {string}", &send_with_expired_session),
    BDD.step(
      "I send {string} to {string} with the origin {string}, the fetch site {string} and the host {string}",
      &send_as_browser,
    ),
    BDD.step("I send {string} to {string} with If-None-Match {string}", &send_if_none_match),
    BDD.step(
      "I send {string} to {string} with the origins {string} and {string} and the host {string}",
      &send_two_origins,
    ),
    BDD.step(
      "I send {string} to {string} with the fetch sites {string} and {string} and the host {string}",
      &send_two_fetch_sites,
    ),
    BDD.step("I send {string} to {string} with the range {string} and the validator {string}", &send_range),
    BDD.step("the header {string} appears {int} times", &header_count_is),
    BDD.step("the header {string} has the value {string}", &header_has_value),
    BDD.step("the header {string} has the value:", &header_has_doc_value),
    BDD.step("the header {string} starts with {string}", &header_starts_with),
    BDD.step("the header {string} ends with {string}", &header_ends_with),
    BDD.step("the status is {int}", &status_is),
    BDD.step("the body is {string}", &body_is),
    BDD.step("the body bytes are {string}", &body_bytes_are),
    BDD.step("the body is the text {string}", &body_is_text),
    BDD.step("the header {string} is {string}", &header_is),
    BDD.step("the header {string} is not set", &header_not_set),
    BDD.step("the body has {int} bytes", &body_size_is),
    BDD.step("the body bytes are the pattern from {int}", &body_is_pattern),
    BDD.step("the JSON body is:", &json_body_is),
    BDD.step("the server listens on a free port", &start_server),
    BDD.step("the server with a small body limit listens on a free port", &start_limited_server),
    BDD.step("I get {string} over the socket", &get_over_socket),
    BDD.step("I get {string} over the socket with the header {string} set to {string}", &get_over_socket_with),
    BDD.step("I post {string} to {string} over the socket", &post_over_socket),
    BDD.step("I post the chunks {string} to {string} over a raw socket", &post_chunks_over_socket),
    BDD.step("the WebSocket server listens on a free port", &start_websocket_server),
    BDD.step("I open a WebSocket to {string} from the origin {string} and send {string}", &open_websocket),
    BDD.step(
      "I open a WebSocket to {string} from the origins {string} and {string} and send {string}",
      &open_websocket_twice,
    ),
    BDD.step("I open a WebSocket to {string} with no origin and send {string}") do |ctx, args|
      talk_websocket(ctx, args[0], [], args[1])
    end,
    BDD.step("I open a WebSocket to {string} with no origin, send {string} and leave", &leave_websocket),
    BDD.step("the server prints {string}", &server_prints),
    BDD.step("the WebSocket answers {string}", &websocket_answers),
    BDD.step("the WebSocket closes with the code {int}", &websocket_closes_with),
  ])
end

def post_bytes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[2])]
  return send(ctx, Ask(method: "POST", path: args[1], headers: headers, body: "", raw: numbers(args[0])))
end

def send_header_and_body(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: args[2], value: args[3])]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: BDD.doc_string(ctx)))
end

def post_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[1])]
  return send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
end

def post_as_two_types(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[1]), Header(name: "content-type", value: args[2])]
  return send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
end

def send_two_cookies(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "cookie", value: args[2]), Header(name: "cookie", value: args[3])]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

# The `name=value` of the session cookie that the last answer set.
def last_session_cookie(ctx: BDD.Context) -> String
  fields = last_reply(ctx).fields.select do |field| field.name.downcase == "set-cookie" end
  return fields.first.value.split(";").first
end

def send_with_last_session(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "cookie", value: last_session_cookie(ctx))]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

# Changes the first character of the payload: the signature no longer matches it.
def send_with_changed_session(ctx: BDD.Context, args: List[String]) -> BDD.Context
  parts = last_session_cookie(ctx).split("=")
  value = parts[1]
  first = value.slice(0, 1)
  other = "A"
  if first == "A"
    other = "B"
  end

  changed = "#{parts[0]}=#{other}#{value.slice(1, value.length - 1)}"
  return send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: changed)], body: ""))
end

def send_with_first_secret(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return send_with_signed(ctx, args, Fixture.session_options(false))
end

def send_with_expired_session(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return send_with_signed(ctx, args, Fixture.expired_options())
end

# A valid cookie of the same secret, signed under the name `other_session` and sent as `_bond_session`.
def send_with_other_name(ctx: BDD.Context, args: List[String]) -> BDD.Context
  options = Bond.SessionOptions(secret: Fixture.session_options(false).secret, name: "other_session")
  cookie = Testing.session_cookie(options, {"user": args[2]}).unwrap!
  moved = "_bond_session=#{cookie.replace("other_session=", "")}"
  return send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: moved)], body: ""))
end

def send_with_signed(ctx: BDD.Context, args: List[String], options: Bond.SessionOptions) -> BDD.Context
  cookie = Testing.session_cookie(options, {"user": args[2]}).unwrap!
  return send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: cookie)], body: ""))
end

# A request as a browser makes it: a header that is "" is not sent.
def send_as_browser(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers: List[Header] = []
  for pair in [["origin", args[2]], ["sec-fetch-site", args[3]], ["host", args[4]]]
    if pair[1] != ""
      headers = headers.push(Header(name: pair[0], value: pair[1]))
    end
  end

  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

# `{etag}` in the value is the `ETag` of the last answer, and `{other}` is a tag that no file has.
def send_if_none_match(ctx: BDD.Context, args: List[String]) -> BDD.Context
  etag = last_reply(ctx).headers.get("etag", "")
  value = args[2].replace("{etag}", etag).replace("{other}", "\"0-0\"")
  return send(
    ctx,
    Ask(method: args[0], path: args[1], headers: [Header(name: "if-none-match", value: value)], body: ""),
  )
end

def send_two_origins(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [
    Header(name: "origin", value: args[2]),
    Header(name: "origin", value: args[3]),
    Header(name: "host", value: args[4]),
  ]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def send_two_fetch_sites(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [
    Header(name: "sec-fetch-site", value: args[2]),
    Header(name: "sec-fetch-site", value: args[3]),
    Header(name: "host", value: args[4]),
  ]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def send_range(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "range", value: args[2]), Header(name: "if-range", value: args[3])]
  return send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def header_count_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  count = reply.fields.select do |field| field.name.downcase == args[0].downcase end.size
  return BDD.assert(ctx, count == args[1].to_i!, "the header appears #{count} times in #{reply.fields}")
end

def header_has_value(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == args[1] end
  return BDD.assert(ctx, found, "the headers are #{reply.fields}")
end

def header_has_doc_value(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  expected = BDD.doc_string(ctx)
  found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == expected end
  return BDD.assert(ctx, found, "the headers are #{reply.fields}")
end

def header_starts_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(
    ctx,
    reply.headers.get(args[0].downcase, "").start_with?(args[1]),
    "the headers are #{reply.headers}",
  )
end

def header_ends_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(
    ctx,
    reply.headers.get(args[0].downcase, "").end_with?(args[1]),
    "the headers are #{reply.headers}",
  )
end

def status_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(ctx, reply.status == args[0].to_i!, "the status is #{reply.status}")
end

def body_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(ctx, reply.body == args[0], "the body is #{reply.body}")
end

def body_bytes_are(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(ctx, reply.bytes == args[0], "the body bytes are #{reply.bytes}")
end

# Like "the body is {string}", for text with line breaks (the events of a stream): the step reads a quoted string as
# Gherkin does, so a backslash is written twice and `\\n` is a line break.
def body_is_text(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  expected = args[0].replace("\\n", "\n")
  return BDD.assert(ctx, reply.body == expected, "the body is #{reply.body.inspect}, not #{expected.inspect}")
end

def header_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(ctx, reply.headers.get(args[0].downcase, "") == args[1], "the headers are #{reply.headers}")
end

def header_not_set(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  return BDD.assert(ctx, not reply.headers.key?(args[0].downcase), "the headers are #{reply.headers}")
end

def body_size_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  count = numbers(reply.bytes).size
  return BDD.assert(ctx, count == args[0].to_i!, "the body has #{count} bytes")
end

def keep_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build(producers), producers)
end

def keep_custom_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_custom(producers), producers)
end

def keep_csrf_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_csrf(false), producers)
end

def keep_allowing_csrf_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_csrf(true), producers)
end

def keep_sessions_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_sessions(false), producers)
end

def keep_rotated_sessions_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_sessions(true), producers)
end

# The folder of the links is made for each request and removed after it, since a scenario has no hook to clean up.
# The scenario is skipped where the folder cannot be made (no `ln`, no links, no file named `con.txt`).
def keep_links_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  base = "static_links_#{System.pid()}"
  probe = make_folder(base)
  Path.remove(base)
  if not probe.ok?
    return BDD.skip(ctx, "the folder of links cannot be made here: #{probe.message}")
  end

  return BDD.keep(ctx, APP) do |request| serve_links(base, request) end
end

def serve_links(base: String, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  try make_folder(base)
  app = Bond.app() |> Bond.static("/files", "#{base}/root")
  response = ask_request(app, ask, 0, 10_000)
  Path.remove(base)
  return ok(JSON.from(reply_of(response)))
end

# `root` has the files and the links, and `secret.txt` next to it is the file that no link may reach.
def make_folder(base: String) -> Result[Void]
  root = "#{base}/root"
  try Dir.mkdir("#{root}/.hid")
  for name in ["hello.txt", "console.txt", "com0.txt", "con.txt", "nul.css", "Aux.html", "com1.txt", "LPT9.txt"]
    try File.write_text("#{root}/#{name}", "hello from a file")
  end

  try File.write_text("#{root}/.env", "hidden")
  try File.write_text("#{root}/.hid/inner.txt", "hidden")
  try File.write_text("#{base}/secret.txt", "outside")
  try link("hello.txt", "#{root}/alias.txt")
  try link(".env", "#{root}/to_env.txt")
  try link(".hid/inner.txt", "#{root}/to_hid.txt")
  try link(".hid", "#{root}/to_hid_dir")
  try link("../secret.txt", "#{root}/outside.txt")
  try link("..", "#{root}/out_dir")
  return ok()
end

def link(target: String, path: String) -> Result[Void]
  process = try Process.spawn("ln", ["-s", target, path])
  code = try Process.wait(process, SOCKET_MS)
  if code != 0
    return error("ln -s exited with #{code}")
  end

  return ok()
end

def keep(ctx: BDD.Context, app: Bond.App, producers: Fixture.Producers) -> BDD.Context
  return BDD.keep(ctx, APP) do |request| serve(app, producers, request) end
end

def serve(app: Bond.App, producers: Fixture.Producers, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  before = Task.pending_count()
  response = ask_request(app, ask, ask.max_pieces, ask.timeout_ms)
  wait_for_producers(producers)
  settle(before)
  return ok(JSON.from(reply_of(response)))
end

# The pump of a file (`Bond.send_file`) is a task of the library, so it is not in `producers`. When the body has been
# read it is about to end, so this waits for the tasks to be back to what they were before the request.
def settle(before: Int) -> Void
  for _ in 1..PRODUCER_MS
    if Task.pending_count() <= before
      return
    end

    Task.sleep(1)
  end
end

# A file of `size` bytes, written for each request in a folder that is removed after it. Byte `i` is `i % 251`
# (a prime,
# so the pattern does not repeat at the size of a piece), which `body_is_pattern` checks. The routes: `/big` sends the
# file, `/save` sends it as a download, and `/files` serves its folder.
def keep_big_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  size = args[0].to_i!
  base = "send_file_#{System.pid()}"
  return BDD.keep(ctx, APP) do |request| serve_big(base, size, request) end
end

def serve_big(base: String, size: Int, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  try Dir.mkdir(base)
  try File.write_bytes(File.open("#{base}/big.bin", "write", SOCKET_MS).unwrap!, pattern(size), SOCKET_MS)
  app = (
    Bond.app()
    |> Bond.get("/big") do |conn| Bond.send_file(conn, "#{base}/big.bin") end
    |> Bond.get("/save") do |conn| Bond.send_file(conn, "#{base}/big.bin", some("big file.bin")) end
    |> Bond.static("/files", base)
  )
  before = Task.pending_count()
  response = ask_request(app, ask, 0, 10_000)
  settle(before)
  Path.remove("#{base}/big.bin")
  Path.remove(base)
  return ok(JSON.from(reply_of(response)))
end

def pattern(size: Int) -> Bytes
  return Bytes.from_list((0...size).to_a.map do |i| i % PATTERN end).unwrap!
end

# The body is the pattern of `keep_big_app` starting at the byte given by the step.
def body_is_pattern(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  start = args[0].to_i!
  values = numbers(reply.bytes)
  wrong = (0...values.size).to_a.select do |i| values[i] != (start + i) % PATTERN end
  return BDD.assert(ctx, wrong.empty?, "the body differs from the pattern at #{wrong.take(3)}")
end

# BDD fails a handler that returns with a task pending, and a producer of a stream ends only when it has seen its
# channel closed (or sent its last piece). The routes of the streams hand their tasks over, and this awaits each, so
# no timing is guessed. By the time `Testing.request` returns, every task that the request started is in the channel.
def wait_for_producers(producers: Fixture.Producers) -> Void
  while true
    case producers.recv(1)
      ok(task) -> Task.await(task, PRODUCER_MS)
      error(_) -> break
    end
  end
end

def send_two_types(ctx: BDD.Context, args: List[String]) -> BDD.Context
  first = Header(name: "content-type", value: args[2])
  second = Header(name: "content-type", value: args[3])
  return send(ctx, Ask(method: args[0], path: args[1], headers: [first, second], body: BDD.doc_string(ctx)))
end

def send(ctx: BDD.Context, ask: Ask) -> BDD.Context
  reply = BDD.call(ctx, APP, JSON.from(ask))
  return BDD.set(ctx, REPLY, reply.unwrap!)
end

# The request of a step: its text body, or its bytes when it has some.
def ask_request(app: Bond.App, ask: Ask, max_pieces: Int, timeout_ms: Int) -> HttpResponse
  if ask.raw.empty?
    return Testing.request(app, ask.method, ask.path, ask.headers, ask.body, max_pieces, timeout_ms)
  end

  body = Bytes.from_list(ask.raw).unwrap!
  return Testing.request_bytes(app, ask.method, ask.path, ask.headers, body, max_pieces, timeout_ms)
end

# "255 254 0" as the numbers it lists.
def numbers(text: String) -> List[Int]
  return text.split(" ").map do |word| word.to_i! end
end

def reply_of(response: HttpResponse) -> Reply
  start: Map[String, String] = {}
  fields = response.headers.reduce(start) do |acc, header| acc.put(header.name.downcase, header.value) end
  text = String.from_bytes(response.body).unwrap_or("")
  values = response.body.to_a.map do |byte| byte.to_s end.join(" ")
  return Reply(status: response.status, headers: fields, fields: response.headers, body: text, bytes: values)
end

def last_reply(ctx: BDD.Context) -> Reply
  return JSON.decode(BDD.get(ctx, REPLY).unwrap!, Reply).unwrap!
end

def json_body_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  body = JSON.parse(reply.body)
  expected = JSON.parse(BDD.doc_string(ctx)).unwrap!
  # The canonical text of a parsed value has sorted keys, so the key order does not matter.
  return BDD.assert(ctx, body.ok? and JSON.encode(body.unwrap!) == JSON.encode(expected), "the body is #{reply.body}")
end

def start_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return start_program(ctx, "fixtures/server.agc")
end

def start_limited_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return start_program(ctx, "fixtures/limited_server.agc")
end

def start_program(ctx: BDD.Context, program: String) -> BDD.Context
  started = BDD.given_program(ctx, program)
  line = BDD.read_line(started, SOCKET_MS).unwrap!
  return BDD.set(started, PORT, JSON.from(line.replace("listening on ", "").to_i!))
end

def get_over_socket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return over_socket(ctx, "GET", args[0], "")
end

def post_over_socket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return over_socket(ctx, "POST", args[1], args[0])
end

def get_over_socket_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return over_socket(ctx, "GET", args[0], "", [Header(name: args[1], value: args[2])])
end

def over_socket(
  ctx: BDD.Context,
  method: String,
  path: String,
  body: String,
  headers: List[Header] = [],
) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(client, method, "http://127.0.0.1:#{port}#{path}", body.bytes, headers)
  HTTP.close_client(client)
  return BDD.set(ctx, REPLY, JSON.from(reply_of(response.unwrap!)))
end

# A chunked `POST` written by hand, since the client of `std/http` always sends a `Content-Length`. In the chunks a `~`
# is a CRLF, so `5~hello~0~~` is one chunk of five bytes and the end of the body. The answer is read as far as its
# `Content-Length`, and the connection is not asked to close, so the `Connection: close` of a refusal is the server's.
def post_chunks_over_socket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  head = "POST #{args[1]} HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n"
  socket = TCP.connect("127.0.0.1", port, SOCKET_MS).unwrap!
  TCP.send(socket, head + args[0].replace("~", "\r\n"), SOCKET_MS).unwrap!
  response = read_raw_answer(socket)
  TCP.close(socket)
  return BDD.set(ctx, REPLY, JSON.from(reply_of(response)))
end

def read_raw_answer(socket: Socket) -> HttpResponse
  status = TCP.read_line(socket, SOCKET_MS).unwrap!.strip.split(" ")[1].to_i!
  headers: List[Header] = []
  line = TCP.read_line(socket, SOCKET_MS).unwrap!.strip
  while not line.empty?
    at = line.index_of(":").unwrap!
    headers = headers.push(Header(name: line.slice(0, at), value: line.slice(at + 1, line.length - at - 1).strip))
    line = TCP.read_line(socket, SOCKET_MS).unwrap!.strip
  end

  # A refusal has `Content-Length: 0`, so no body is read; an answer without one (a streamed one) would read as empty.
  wanted = HTTP.header_values(headers, "content-length").map do |value| value.to_i! end.reduce(0) do |_, size| size end
  body = "".bytes
  while body.size < wanted
    body = Bytes.concat([body, TCP.recv_bytes(socket, wanted - body.size, SOCKET_MS).unwrap!])
  end

  return HttpResponse(status: status, headers: headers, body: body)
end

def start_websocket_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return start_program(ctx, "fixtures/websocket_server.agc")
end

# `PORT` in the origin is the port of the server, so "http://127.0.0.1:PORT" is the origin of its own pages.
def open_websocket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  origin = Header(name: "Origin", value: args[1].replace("PORT", port.to_s))
  return talk_websocket(ctx, args[0], [origin], args[2])
end

# Two `Origin` headers, which no browser sends.
def open_websocket_twice(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  origins = [args[1], args[2]].map do |origin| Header(name: "Origin", value: origin.replace("PORT", port.to_s)) end
  return talk_websocket(ctx, args[0], origins, args[3])
end

# A WebSocket client written by hand, since `std/http` has none: the handshake of RFC 6455, then, when the answer is
# a 101, one masked text frame, the server's answer to it, and the closing handshake. The head of the answer is the
# reply of the step, and what the WebSocket heard is kept under `WEBSOCKET`.
def talk_websocket(ctx: BDD.Context, path: String, headers: List[Header], text: String) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  socket = TCP.connect("127.0.0.1", port, SOCKET_MS).unwrap!
  TCP.send(socket, handshake(path, port, headers), SOCKET_MS).unwrap!
  response = read_raw_answer(socket)
  heard = Heard(answer: "", close_code: 0)
  if response.status == 101
    heard = converse(socket, text)
  end

  TCP.close(socket)
  replied = BDD.set(ctx, REPLY, JSON.from(reply_of(response)))
  return BDD.set(replied, WEBSOCKET, JSON.from(heard))
end

# The handshake of RFC 6455 for `path`, with the extra `headers`.
def handshake(path: String, port: Int, headers: List[Header]) -> String
  fields = [
    "Host: 127.0.0.1:#{port}",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: #{WEBSOCKET_KEY}",
    "Sec-WebSocket-Version: 13",
  ]
  lines = fields.concat(headers.map do |field| "#{field.name}: #{field.value}" end)
  return "GET #{path} HTTP/1.1\r\n#{lines.join("\r\n")}\r\n\r\n"
end

# One message and its answer, then the close: the client sends a close frame after the answer, and reads frames until
# the server's close frame. A server that closes first (a handler that crashed) is answered with nothing more.
def converse(socket: Socket, text: String) -> Heard
  send_frame(socket, TEXT_FRAME, text.bytes)
  first = read_frame(socket)
  if first.opcode == CLOSE_FRAME
    return Heard(answer: "", close_code: close_code(first.payload))
  end

  answer = String.from_bytes(first.payload).unwrap!
  send_frame(socket, CLOSE_FRAME, Bytes.from_list([NORMAL_CLOSE / BYTE, NORMAL_CLOSE % BYTE]).unwrap!)
  frame = read_frame(socket)
  while frame.opcode != CLOSE_FRAME
    frame = read_frame(socket)
  end

  return Heard(answer: answer, close_code: close_code(frame.payload))
end

# A final frame from the client, masked as RFC 6455 requires, with a payload of at most 125 bytes.
def send_frame(socket: Socket, opcode: Int, payload: Bytes) -> Void
  values = payload.to_a
  masked = (0...values.size).to_a.map do |at| Int.bit_xor(values[at], MASK[at % MASK.size]) end
  head = [FINAL_BIT + opcode, MASK_BIT + values.size]
  TCP.send_bytes(socket, Bytes.from_list(head.concat(MASK).concat(masked)).unwrap!, SOCKET_MS).unwrap!
end

# A frame from the server, which is never masked: a length of up to 125, or 126 and two bytes of length.
def read_frame(socket: Socket) -> Frame
  head = read_exactly(socket, 2).to_a
  size = Int.bit_and(head[1], LENGTH_BITS)
  if size == TWO_BYTE_LENGTH
    longer = read_exactly(socket, 2).to_a
    size = longer[0] * BYTE + longer[1]
  end

  return Frame(opcode: Int.bit_and(head[0], 15), payload: read_exactly(socket, size))
end

def read_exactly(socket: Socket, size: Int) -> Bytes
  got = "".bytes
  while got.size < size
    got = Bytes.concat([got, TCP.recv_bytes(socket, size - got.size, SOCKET_MS).unwrap!])
  end

  return got
end

# The status code of a close frame: its first two bytes, or 1005 (none) when it has none.
def close_code(payload: Bytes) -> Int
  values = payload.to_a
  if values.size < 2
    return 1005
  end

  return values[0] * BYTE + values[1]
end

def heard(ctx: BDD.Context) -> Heard
  return JSON.decode(BDD.get(ctx, WEBSOCKET).unwrap!, Heard).unwrap!
end

def websocket_answers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  answer = heard(ctx).answer
  return BDD.assert(ctx, answer == args[0], "the WebSocket answered #{answer.inspect}")
end

def websocket_closes_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  code = heard(ctx).close_code
  return BDD.assert(ctx, code == args[0].to_i!, "the WebSocket closed with #{code}")
end

# A client that goes away without the closing handshake: it reads the answer to its message and closes the socket.
def leave_websocket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  socket = TCP.connect("127.0.0.1", port, SOCKET_MS).unwrap!
  TCP.send(socket, handshake(args[0], port, []), SOCKET_MS).unwrap!
  response = read_raw_answer(socket)
  send_frame(socket, TEXT_FRAME, args[1].bytes)
  answer = String.from_bytes(read_frame(socket).payload).unwrap!
  TCP.close(socket)
  replied = BDD.set(ctx, REPLY, JSON.from(reply_of(response)))
  return BDD.set(replied, WEBSOCKET, JSON.from(Heard(answer: answer, close_code: 0)))
end

def server_prints(ctx: BDD.Context, args: List[String]) -> BDD.Context
  line = BDD.read_line(ctx, SOCKET_MS).unwrap_or("")
  return BDD.assert(ctx, line == args[0], "the server printed #{line.inspect}")
end
