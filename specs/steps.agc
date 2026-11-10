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
UPLOAD_BOUNDARY = "bond-spec-boundary"
WEBSOCKET = "websocket"
# The key of RFC 6455 section 1.3, whose `Sec-WebSocket-Accept` is known.
WEBSOCKET_KEY = "dGhlIHNhbXBsZSBub25jZQ=="
TEXT_FRAME = 1
CLOSE_FRAME = 8
PING_FRAME = 9
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
  remote_addr: String = "127.0.0.1" # keep in sync with Testing.LOOPBACK
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
    BDD.step("the assigns app", &keep_assigns_app),
    BDD.step("the sessions app", &keep_sessions_app),
    BDD.step("the sessions app after the secret was rotated", &keep_rotated_sessions_app),
    BDD.step("the app with CSRF protection", &keep_csrf_app),
    BDD.step("the app with CSRF protection that allows https://admin.example.net", &keep_allowing_csrf_app),
    BDD.step("the app with a file of {int} bytes", &keep_big_app),
    BDD.step("the app with a cache of {int} bytes over a folder that I edit", &keep_edit_app),
    BDD.step("the file {string} holds {string} as of the time {int}", &write_file_at),
    BDD.step("the file {string} holds the gzip of {string} as of the time {int}", &write_gzip_at),
    BDD.step("the outside file holds {string}", &write_outside),
    BDD.step("the file {string} is a link to the outside file", &link_to_outside),
    BDD.step("the file {string} is removed", &remove_file),
    BDD.step("I send {string} to {string} with the headers:", &send_with_table),
    BDD.step("the body gunzipped is {string}", &gunzipped_is),
    BDD.step("the body gunzipped is the file {string}", &gunzipped_is_file),
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
    BDD.step("I send {string} to {string} from the address {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: "", remote_addr: args[2]))
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
    BDD.step("the upload server listens on a free port", &start_upload_server),
    BDD.step(
      "I post the fields {string} and the file {string} holding {string} to {string} over the socket",
      &post_upload,
    ),
    BDD.step("I post the fields {string} and a file of {int} bytes to {string} over the socket") do |ctx, args|
      send_upload(ctx, args[0], "big.bin", List.repeat("x", args[1].to_i!).join(""), args[2])
    end,
    BDD.step("I post a text field of {int} bytes and a file to {string} over the socket") do |ctx, args|
      send_upload(ctx, "title=#{List.repeat("y", args[0].to_i!).join("")}", "a.txt", "small", args[1])
    end,
    BDD.step("I post the file {string} holding {string} to {string} over the socket from another site") do |ctx, args|
      send_upload(ctx, "title=x", args[0], args[1], args[2], [Header(name: "sec-fetch-site", value: "cross-site")])
    end,
    BDD.step("the body has the line {string}", &body_has_line),
    BDD.step("the saved file of the answer is removed", &saved_file_removed),
    BDD.step("the saved path of the answer does not have {string}", &saved_path_lacks),
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
    BDD.step("I open a WebSocket to {string} with no origin and say nothing", &stay_silent),
    BDD.step("the server prints {string}", &server_prints),
    BDD.step("the WebSocket answers {string}", &websocket_answers),
    BDD.step("the WebSocket closes with the code {int}", &websocket_closes_with),
  ])
end

def post_bytes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[2])]
  send(ctx, Ask(method: "POST", path: args[1], headers: headers, body: "", raw: numbers(args[0])))
end

def send_header_and_body(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: args[2], value: args[3])]
  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: BDD.doc_string(ctx)))
end

def post_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[1])]
  send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
end

def post_as_two_types(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "content-type", value: args[1]), Header(name: "content-type", value: args[2])]
  send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
end

def send_two_cookies(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "cookie", value: args[2]), Header(name: "cookie", value: args[3])]
  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

# The `name=value` of the session cookie that the last answer set.
def last_session_cookie(ctx: BDD.Context) -> String
  fields = last_reply(ctx).fields.select do |field| field.name.downcase == "set-cookie" end
  fields.first.value.split(";").first
end

def send_with_last_session(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "cookie", value: last_session_cookie(ctx))]
  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
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
  send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: changed)], body: ""))
end

def send_with_first_secret(ctx: BDD.Context, args: List[String]) -> BDD.Context
  send_with_signed(ctx, args, Fixture.session_options(false))
end

def send_with_expired_session(ctx: BDD.Context, args: List[String]) -> BDD.Context
  send_with_signed(ctx, args, Fixture.expired_options())
end

# A valid cookie of the same secret, signed under the name `other_session` and sent as `_bond_session`.
def send_with_other_name(ctx: BDD.Context, args: List[String]) -> BDD.Context
  options = Bond.SessionOptions(secret: Fixture.session_options(false).secret, name: "other_session")
  cookie = Testing.session_cookie(options, {"user": args[2]}).unwrap!
  moved = "_bond_session=#{cookie.replace("other_session=", "")}"
  send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: moved)], body: ""))
end

def send_with_signed(ctx: BDD.Context, args: List[String], options: Bond.SessionOptions) -> BDD.Context
  cookie = Testing.session_cookie(options, {"user": args[2]}).unwrap!
  send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: cookie)], body: ""))
end

# A request as a browser makes it: a header that is "" is not sent.
def send_as_browser(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers: List[Header] = []
  for pair in [["origin", args[2]], ["sec-fetch-site", args[3]], ["host", args[4]]]
    if pair[1] != ""
      headers = headers.push(Header(name: pair[0], value: pair[1]))
    end
  end

  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

# The headers of the table, one `| name | value |` row each. `{etag}` and `{last_modified}` in a value are the headers
# of the last answer, and `{other}` is a tag that no file has.
def send_with_table(ctx: BDD.Context, args: List[String]) -> BDD.Context
  last = Reply(status: 0, headers: {}, fields: [], body: "", bytes: "")
  if BDD.get(ctx, REPLY).ok?
    last = last_reply(ctx)
  end

  headers = BDD.table(ctx).map do |row| Header(name: row[0], value: filled(row[1], last)) end
  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def filled(value: String, last: Reply) -> String
  tagged = value.replace("{etag}", last.headers.get("etag", ""))
  tagged.replace("{last_modified}", last.headers.get("last-modified", "")).replace("{other}", "\"0-0\"")
end

# `{etag}` in the value is the `ETag` of the last answer, and `{other}` is a tag that no file has.
def send_if_none_match(ctx: BDD.Context, args: List[String]) -> BDD.Context
  etag = last_reply(ctx).headers.get("etag", "")
  value = args[2].replace("{etag}", etag).replace("{other}", "\"0-0\"")
  send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "if-none-match", value: value)], body: ""))
end

def send_two_origins(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [
    Header(name: "origin", value: args[2]),
    Header(name: "origin", value: args[3]),
    Header(name: "host", value: args[4]),
  ]

  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def send_two_fetch_sites(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [
    Header(name: "sec-fetch-site", value: args[2]),
    Header(name: "sec-fetch-site", value: args[3]),
    Header(name: "host", value: args[4]),
  ]

  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def send_range(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [Header(name: "range", value: args[2]), Header(name: "if-range", value: args[3])]
  send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
end

def header_count_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  count = reply.fields.select do |field| field.name.downcase == args[0].downcase end.size
  BDD.assert(ctx, count == args[1].to_i!, "the header appears #{count} times in #{reply.fields}")
end

def header_has_value(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == args[1] end
  BDD.assert(ctx, found, "the headers are #{reply.fields}")
end

def header_has_doc_value(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  expected = BDD.doc_string(ctx)
  found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == expected end
  BDD.assert(ctx, found, "the headers are #{reply.fields}")
end

def header_starts_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.headers.get(args[0].downcase, "").start_with?(args[1]), "the headers are #{reply.headers}")
end

def header_ends_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.headers.get(args[0].downcase, "").end_with?(args[1]), "the headers are #{reply.headers}")
end

def status_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.status == args[0].to_i!, "the status is #{reply.status}")
end

def body_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.body == args[0], "the body is #{reply.body}")
end

def body_bytes_are(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.bytes == args[0], "the body bytes are #{reply.bytes}")
end

# Like "the body is {string}", for text with line breaks (the events of a stream): the step reads a quoted string as
# Gherkin does, so a backslash is written twice and `\\n` is a line break.
def body_is_text(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  expected = args[0].replace("\\n", "\n")
  BDD.assert(ctx, reply.body == expected, "the body is #{reply.body.inspect}, not #{expected.inspect}")
end

def header_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, reply.headers.get(args[0].downcase, "") == args[1], "the headers are #{reply.headers}")
end

def header_not_set(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  BDD.assert(ctx, not reply.headers.key?(args[0].downcase), "the headers are #{reply.headers}")
end

def body_size_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  count = numbers(reply.bytes).size
  BDD.assert(ctx, count == args[0].to_i!, "the body has #{count} bytes")
end

def gunzipped_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  text = gunzipped(last_reply(ctx))
  BDD.assert(ctx, text == args[0], "the body gunzipped is #{text}")
end

def gunzipped_is_file(ctx: BDD.Context, args: List[String]) -> BDD.Context
  text = gunzipped(last_reply(ctx))
  expected = File.read_text(args[0]).unwrap_or("")
  BDD.assert(ctx, not expected.empty? and text == expected, "the body gunzipped is #{text}")
end

# The text of a gzip body, or "" when the body is not gzip.
def gunzipped(reply: Reply) -> String
  data = Bytes.from_list(reply.bytes.split(" ").select do |word| not word.empty? end.map do |word| word.to_i! end)
  packed = Zlib.gunzip(data.unwrap_or("".bytes))
  String.from_bytes(packed.unwrap_or("".bytes)).unwrap_or("")
end

def keep_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build(producers), producers)
end

def keep_custom_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_custom(producers), producers)
end

def keep_csrf_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_csrf(false), producers)
end

def keep_allowing_csrf_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_csrf(true), producers)
end

def keep_assigns_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_assigns(), producers)
end

def keep_sessions_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_sessions(false), producers)
end

def keep_rotated_sessions_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  keep(ctx, Fixture.build_sessions(true), producers)
end

# The folder of the links is made for each request and removed after it, since a scenario has no hook to clean up.
# The scenario is skipped where the folder cannot be made (no `ln`, no links, no file named `con.txt`).
def keep_links_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  base = "static_links_#{System.pid()}"
  probe = make_folder(base)
  _ = Path.remove(base)
  return BDD.skip(ctx, "the folder of links cannot be made here: #{probe.message}") if not probe.ok?

  BDD.keep(ctx, APP) do |request| serve_links(base, request) end
end

def serve_links(base: String, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  try make_folder(base)
  app = Bond.app() |> Bond.static("/files", "#{base}/root")
  response = ask_request(app, ask, 0, 10_000)
  _ = Path.remove(base)
  ok(JSON.from(reply_of(response)))
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
  ok()
end

def link(target: String, path: String) -> Result[Void]
  process = try Process.spawn("ln", ["-s", target, path])
  code = try Process.wait(process, SOCKET_MS)
  return error("ln -s exited with #{code}") if code != 0

  ok()
end

def keep(ctx: BDD.Context, app: Bond.App, producers: Fixture.Producers) -> BDD.Context
  BDD.keep(ctx, APP) do |request| serve(app, producers, request) end
end

def serve(app: Bond.App, producers: Fixture.Producers, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  before = Task.pending_count()
  response = ask_request(app, ask, ask.max_pieces, ask.timeout_ms)
  wait_for_producers(producers)
  settle(before)
  ok(JSON.from(reply_of(response)))
end

# The pump of a file (`Bond.send_file`) is a task of the library, so it is not in `producers`. When the body has been
# read it is about to end, so this waits for the tasks to be back to what they were before the request.
def settle(before: Int) -> Void
  for _ in 1..PRODUCER_MS
    return if Task.pending_count() <= before

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
  BDD.keep(ctx, APP) do |request| serve_big(base, size, request) end
end

def serve_big(base: String, size: Int, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  try Dir.mkdir(base)
  try File.write_bytes(File.open("#{base}/big.bin", "write", SOCKET_MS).unwrap!, pattern(size), SOCKET_MS)
  app = (
    Bond.app()
    |> Bond.get("/big") do |conn| Bond.send_file(conn, "#{base}/big.bin") end
    |> Bond.get("/save") do |conn| Bond.send_file(conn, "#{base}/big.bin", some("big file.bin")) end
    |> Bond.get("/pieces") do |conn| Bond.send_file(conn, "#{base}/big.bin", none, none, false, 4_096) end
    |> Bond.get("/whole") do |conn| Bond.send_file(conn, "#{base}/big.bin", none, none, false, 1_048_576) end
    |> Bond.get("/bad-piece") do |conn| Bond.send_file(conn, "#{base}/big.bin", none, none, false, 16_777_217) end
    |> Bond.static("/files", base)
    |> Bond.static("/pieces-files", base, 1_073_741_824, 0, false, 0, 4_096)
    |> Bond.static("/whole-files", base, 1_073_741_824, 0, false, 1_048_576, 1_048_576)
  )

  before = Task.pending_count()
  response = ask_request(app, ask, 0, 10_000)
  settle(before)
  _ = Path.remove("#{base}/big.bin")
  _ = Path.remove(base)
  ok(JSON.from(reply_of(response)))
end

# A folder that a scenario edits between requests, served at `/files` with a cache of the given size, and its `a.txt`
# sent at `/sent`. The app lives for the whole scenario, so its cache does too; the folder is removed when it ends.
def keep_edit_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  base = edit_folder()
  made = Dir.mkdir(base)
  return BDD.skip(ctx, "the folder of the edits cannot be made here: #{made.message}") if not made.ok?

  app = (
    Bond.app()
    |> Bond.get("/sent") do |conn| Bond.send_file(conn, "#{base}/a.txt") end
    |> Bond.static("/files", base, 1_073_741_824, 0, false, args[0].to_i!)
    |> Bond.static("/versioned", base, 1_073_741_824, 0, true, args[0].to_i!)
  )

  kept = BDD.keep(ctx, APP) do |request| serve_edited(app, request) end
  BDD.after(kept) do |_| remove_folder(base) end
end

def edit_folder() -> String = "edit_files_#{System.pid()}"

def serve_edited(app: Bond.App, request: Json) -> Result[Json]
  ask = try JSON.decode(request, Ask)
  before = Task.pending_count()
  response = ask_request(app, ask, 0, 10_000)
  settle(before)
  ok(JSON.from(reply_of(response)))
end

def remove_folder(base: String) -> Result[Void]
  names = try Dir.list(base)
  for name in names
    _ = Path.remove("#{base}/#{name}")
  end

  _ = Path.remove(base)
  _ = Path.remove(outside_file())
  ok()
end

# Writes the file and sets its time of change to `seconds` after the epoch, so a scenario knows the `Last-Modified`.
def write_file_at(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = "#{edit_folder()}/#{args[0]}"
  written = File.write_text(path, args[1])
  return BDD.skip(ctx, "the file cannot be written here: #{written.message}") if not written.ok?

  set = set_time(path, args[2].to_i!)
  return BDD.skip(ctx, "the time of a file cannot be set here: #{set.message}") if not set.ok?

  ctx
end

# The gzip of the text, as a build that compresses its files would leave it next to the file.
def write_gzip_at(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = "#{edit_folder()}/#{args[0]}"
  packed = Zlib.gzip(args[1].bytes).unwrap!
  written = File.open(path, "write", SOCKET_MS).unwrap!
  _ = File.write_bytes(written, packed, SOCKET_MS)
  _ = File.close(written, SOCKET_MS)
  set = set_time(path, args[2].to_i!)
  return BDD.skip(ctx, "the time of a file cannot be set here: #{set.message}") if not set.ok?

  ctx
end

# A file next to the folder, not in it: what a link of the folder must not reach.
def outside_file() -> String = "#{edit_folder()}_outside.txt"

def write_outside(ctx: BDD.Context, args: List[String]) -> BDD.Context
  written = File.write_text(outside_file(), args[0])
  BDD.assert(ctx, written.ok?, "the outside file is not written")
end

def link_to_outside(ctx: BDD.Context, args: List[String]) -> BDD.Context
  linked = link(Path.resolve(outside_file()).unwrap!, "#{edit_folder()}/#{args[0]}")
  return BDD.skip(ctx, "a link cannot be made here: #{linked.message}") if not linked.ok?

  ctx
end

def remove_file(ctx: BDD.Context, args: List[String]) -> BDD.Context
  removed = Path.remove("#{edit_folder()}/#{args[0]}")
  BDD.assert(ctx, removed.ok?, "the file is not removed")
end

def set_time(path: String, seconds: Int) -> Result[Void]
  process = try Process.spawn("touch", ["-d", "@#{seconds}", path])
  code = try Process.wait(process, SOCKET_MS)
  return error("touch exited with #{code}") if code != 0

  ok()
end

def pattern(size: Int) -> Bytes = Bytes.from_list((0...size).to_a.map do |i| i % PATTERN end).unwrap!

# The body is the pattern of `keep_big_app` starting at the byte given by the step.
def body_is_pattern(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  start = args[0].to_i!
  values = numbers(reply.bytes)
  wrong = (0...values.size).to_a.select do |i| values[i] != (start + i) % PATTERN end
  BDD.assert(ctx, wrong.empty?, "the body differs from the pattern at #{wrong.take(3)}")
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
  send(ctx, Ask(method: args[0], path: args[1], headers: [first, second], body: BDD.doc_string(ctx)))
end

def send(ctx: BDD.Context, ask: Ask) -> BDD.Context
  reply = BDD.call(ctx, APP, JSON.from(ask))
  BDD.set(ctx, REPLY, reply.unwrap!)
end

# The request of a step: its text body, or its bytes when it has some.
def ask_request(app: Bond.App, ask: Ask, max_pieces: Int, timeout_ms: Int) -> HttpResponse
  if ask.raw.empty?
    return Testing.request(app, ask.method, ask.path, ask.headers, ask.body, max_pieces, timeout_ms, ask.remote_addr)
  end

  body = Bytes.from_list(ask.raw).unwrap!
  Testing.request_bytes(app, ask.method, ask.path, ask.headers, body, max_pieces, timeout_ms, ask.remote_addr)
end

# "255 254 0" as the numbers it lists.
def numbers(text: String) -> List[Int] = text.split(" ").map do |word| word.to_i! end

def reply_of(response: HttpResponse) -> Reply
  start: Map[String, String] = {}
  fields = response.headers.reduce(start) do |acc, header| acc.put(header.name.downcase, header.value) end
  text = String.from_bytes(response.body).unwrap_or("")
  values = response.body.to_a.map do |byte| byte.to_s end.join(" ")
  Reply(status: response.status, headers: fields, fields: response.headers, body: text, bytes: values)
end

def last_reply(ctx: BDD.Context) -> Reply = JSON.decode(BDD.get(ctx, REPLY).unwrap!, Reply).unwrap!

def json_body_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  reply = last_reply(ctx)
  body = JSON.parse(reply.body)
  expected = JSON.parse(BDD.doc_string(ctx)).unwrap!
  # The canonical text of a parsed value has sorted keys, so the key order does not matter.
  BDD.assert(ctx, body.ok? and JSON.encode(body.unwrap!) == JSON.encode(expected), "the body is #{reply.body}")
end

def start_server(ctx: BDD.Context, args: List[String]) -> BDD.Context = start_program(ctx, "fixtures/server.agc")

def start_limited_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  start_program(ctx, "fixtures/limited_server.agc")
end

def start_program(ctx: BDD.Context, program: String) -> BDD.Context
  started = BDD.given_program(ctx, program)
  line = BDD.read_line(started, SOCKET_MS).unwrap!
  BDD.set(started, PORT, JSON.from(line.replace("listening on ", "").to_i!))
end

def get_over_socket(ctx: BDD.Context, args: List[String]) -> BDD.Context = over_socket(ctx, "GET", args[0], "")

def post_over_socket(ctx: BDD.Context, args: List[String]) -> BDD.Context = over_socket(ctx, "POST", args[1], args[0])

def get_over_socket_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  over_socket(ctx, "GET", args[0], "", [Header(name: args[1], value: args[2])])
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
  BDD.set(ctx, REPLY, JSON.from(reply_of(response.unwrap!)))
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
  BDD.set(ctx, REPLY, JSON.from(reply_of(response)))
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

  HttpResponse(status: status, headers: headers, body: body)
end

def start_websocket_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  start_program(ctx, "fixtures/websocket_server.agc")
end

# `PORT` in the origin is the port of the server, so "http://127.0.0.1:PORT" is the origin of its own pages.
def open_websocket(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  origin = Header(name: "Origin", value: args[1].replace("PORT", port.to_s))
  talk_websocket(ctx, args[0], [origin], args[2])
end

# Two `Origin` headers, which no browser sends.
def open_websocket_twice(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  origins = [args[1], args[2]].map do |origin| Header(name: "Origin", value: origin.replace("PORT", port.to_s)) end
  talk_websocket(ctx, args[0], origins, args[3])
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
  BDD.set(replied, WEBSOCKET, JSON.from(heard))
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
  "GET #{path} HTTP/1.1\r\n#{lines.join("\r\n")}\r\n\r\n"
end

# One message and its answer, then the close: the client sends a close frame after the answer, and reads frames until
# the server's close frame. A server that closes first (a handler that crashed) is answered with nothing more.
def converse(socket: Socket, text: String) -> Heard
  send_frame(socket, TEXT_FRAME, text.bytes)
  first = read_frame(socket)
  return Heard(answer: "", close_code: close_code(first.payload)) if first.opcode == CLOSE_FRAME

  answer = String.from_bytes(first.payload).unwrap!
  send_frame(socket, CLOSE_FRAME, Bytes.from_list([NORMAL_CLOSE / BYTE, NORMAL_CLOSE % BYTE]).unwrap!)
  frame = read_frame(socket)
  while frame.opcode != CLOSE_FRAME
    frame = read_frame(socket)
  end

  Heard(answer: answer, close_code: close_code(frame.payload))
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

  Frame(opcode: Int.bit_and(head[0], 15), payload: read_exactly(socket, size))
end

def read_exactly(socket: Socket, size: Int) -> Bytes
  got = "".bytes
  while got.size < size
    got = Bytes.concat([got, TCP.recv_bytes(socket, size - got.size, SOCKET_MS).unwrap!])
  end

  got
end

# The status code of a close frame: its first two bytes, or 1005 (none) when it has none.
def close_code(payload: Bytes) -> Int
  values = payload.to_a
  return 1005 if values.size < 2

  values[0] * BYTE + values[1]
end

def heard(ctx: BDD.Context) -> Heard = JSON.decode(BDD.get(ctx, WEBSOCKET).unwrap!, Heard).unwrap!

def websocket_answers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  answer = heard(ctx).answer
  BDD.assert(ctx, answer == args[0], "the WebSocket answered #{answer.inspect}")
end

def websocket_closes_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  code = heard(ctx).close_code
  BDD.assert(ctx, code == args[0].to_i!, "the WebSocket closed with #{code}")
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
  BDD.set(replied, WEBSOCKET, JSON.from(Heard(answer: answer, close_code: 0)))
end

def server_prints(ctx: BDD.Context, args: List[String]) -> BDD.Context
  line = BDD.read_line(ctx, SOCKET_MS).unwrap_or("")
  BDD.assert(ctx, line == args[0], "the server printed #{line.inspect}")
end

# A client that opens a WebSocket and sends nothing, not even a pong to the server's pings: it reads what the server
# sends until the server ends the connection (an empty read) or `SOCKET_MS` passes. `answer` is "ping" when the first
# frame was a ping.
def stay_silent(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  socket = TCP.connect("127.0.0.1", port, SOCKET_MS).unwrap!
  TCP.send(socket, handshake(args[0], port, []), SOCKET_MS).unwrap!
  response = read_raw_answer(socket)
  first = ""
  if response.status == 101 and read_frame(socket).opcode == PING_FRAME
    first = "ping"
  end

  piece = TCP.recv_bytes(socket, 1024, SOCKET_MS)
  while piece.ok? and not piece.unwrap!.empty?
    piece = TCP.recv_bytes(socket, 1024, SOCKET_MS)
  end

  TCP.close(socket)
  replied = BDD.set(ctx, REPLY, JSON.from(reply_of(response)))
  BDD.set(replied, WEBSOCKET, JSON.from(Heard(answer: first, close_code: 0)))
end

def start_upload_server(ctx: BDD.Context, args: List[String]) -> BDD.Context
  start_program(ctx, "fixtures/upload_server.agc")
end

def post_upload(ctx: BDD.Context, args: List[String]) -> BDD.Context
  send_upload(ctx, args[0], args[1], args[2], args[3])
end

# A `multipart/form-data` POST written by hand: the fields of `fields` (`name=value&...`, not encoded) and one file
# in the field `photo`, sent by the client of `std/http` with its `Content-Length` and the `headers`.
def send_upload(
  ctx: BDD.Context,
  fields: String,
  filename: String,
  content: String,
  path: String,
  headers: List[Header] = [],
) -> BDD.Context
  parts = fields.split("&").map do |pair|
    at = pair.index_of("=").unwrap!
    name = pair.slice(0, at)
    value = pair.slice(at + 1, pair.length - at - 1)
    "--#{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
  end

  disposition = "Content-Disposition: form-data; name=\"photo\"; filename=\"#{filename}\""
  file = "--#{UPLOAD_BOUNDARY}\r\n#{disposition}\r\nContent-Type: text/plain\r\n\r\n#{content}\r\n"
  body = "#{parts.join("")}#{file}--#{UPLOAD_BOUNDARY}--\r\n"
  content_type = Header(name: "content-type", value: "multipart/form-data; boundary=#{UPLOAD_BOUNDARY}")
  over_socket(ctx, "POST", path, body, headers.push(content_type))
end

def body_has_line(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = last_reply(ctx).body
  BDD.assert(ctx, body.split("\n").any? do |line| line == args[0] end, "the body is #{body.inspect}")
end

# The path line of the answer of `upload_server.agc`.
def saved_path(ctx: BDD.Context) -> String
  lines = last_reply(ctx).body.split("\n").select do |line| line.start_with?("path ") end
  return "" if lines.empty?

  lines[0].slice(5, lines[0].length - 5)
end

def saved_file_removed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = saved_path(ctx)
  BDD.assert(ctx, path != "" and not File.stat(path).ok?, "the file #{path} is still there")
end

def saved_path_lacks(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = saved_path(ctx)
  BDD.assert(ctx, path != "" and not path.include?(args[0]), "the saved path is #{path}")
end
