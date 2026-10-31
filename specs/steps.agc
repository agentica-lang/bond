## The steps of the features. A scenario drives the app of `fixtures/app.agc` in process through `Testing.request`
## (no socket), except the steps of the server, which talk to the program of `fixtures/server.agc` over a socket.

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

struct Ask
  method: String
  path: String
  headers: List[Header]
  body: String
  raw: List[Int] = [] # the body as bytes when it is not empty (then `body` is not used)
  max_pieces: Int = 0
  timeout_ms: Int = 10_000 # keep in sync with the defaults of Testing.request
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
    BDD.step("I post the bytes {string} to {string} as {string}") do |ctx, args|
      headers = [Header(name: "content-type", value: args[2])]
      send(ctx, Ask(method: "POST", path: args[1], headers: headers, body: "", raw: numbers(args[0])))
    end,
    BDD.step("I send {string} to {string} with the header {string} set to {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: args[2], value: args[3])], body: ""))
    end,
    BDD.step("I send {string} to {string} with the header {string} set to {string} and the body:") do |ctx, args|
      headers = [Header(name: args[2], value: args[3])]
      send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: BDD.doc_string(ctx)))
    end,
    BDD.step(
      "I send {string} to {string} with the content types {string} and {string} and the body:",
      &send_two_types,
    ),
    BDD.step("I post to {string} as {string}:") do |ctx, args|
      headers = [Header(name: "content-type", value: args[1])]
      send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
    end,
    BDD.step("I post to {string} as {string} and {string}:") do |ctx, args|
      headers = [Header(name: "content-type", value: args[1]), Header(name: "content-type", value: args[2])]
      send(ctx, Ask(method: "POST", path: args[0], headers: headers, body: BDD.doc_string(ctx)))
    end,
    BDD.step("I send {string} to {string} with the cookie {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [Header(name: "cookie", value: args[2])], body: ""))
    end,
    BDD.step("I send {string} to {string} with the cookies {string} and {string}") do |ctx, args|
      headers = [Header(name: "cookie", value: args[2]), Header(name: "cookie", value: args[3])]
      send(ctx, Ask(method: args[0], path: args[1], headers: headers, body: ""))
    end,
    BDD.step("the header {string} appears {int} times") do |ctx, args|
      reply = last_reply(ctx)
      count = reply.fields.select do |field| field.name.downcase == args[0].downcase end.size
      BDD.assert(ctx, count == args[1].to_i!, "the header appears #{count} times in #{reply.fields}")
    end,
    BDD.step("the header {string} has the value {string}") do |ctx, args|
      reply = last_reply(ctx)
      found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == args[1] end
      BDD.assert(ctx, found, "the headers are #{reply.fields}")
    end,
    BDD.step("the header {string} has the value:") do |ctx, args|
      reply = last_reply(ctx)
      expected = BDD.doc_string(ctx)
      found = reply.fields.any? do |field| field.name.downcase == args[0].downcase and field.value == expected end
      BDD.assert(ctx, found, "the headers are #{reply.fields}")
    end,
    BDD.step("the status is {int}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.status == args[0].to_i!, "the status is #{reply.status}")
    end,
    BDD.step("the body is {string}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.body == args[0], "the body is #{reply.body}")
    end,
    BDD.step("the body bytes are {string}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.bytes == args[0], "the body bytes are #{reply.bytes}")
    end,
    # Like "the body is {string}", for text with line breaks (the events of a stream): the step reads a quoted string as
    # Gherkin does, so a backslash is written twice and `\\n` is a line break.
    BDD.step("the body is the text {string}") do |ctx, args|
      reply = last_reply(ctx)
      expected = args[0].replace("\\n", "\n")
      BDD.assert(ctx, reply.body == expected, "the body is #{reply.body.inspect}, not #{expected.inspect}")
    end,
    BDD.step("the header {string} is {string}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.headers.get(args[0].downcase, "") == args[1], "the headers are #{reply.headers}")
    end,
    BDD.step("the header {string} is not set") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, not reply.headers.key?(args[0].downcase), "the headers are #{reply.headers}")
    end,
    BDD.step("the JSON body is:", &json_body_is),
    BDD.step("the server listens on a free port", &start_server),
    BDD.step("the server with a small body limit listens on a free port", &start_limited_server),
    BDD.step("I get {string} over the socket", &get_over_socket),
    BDD.step("I post {string} to {string} over the socket", &post_over_socket),
  ])
end

def keep_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build(producers), producers)
end

def keep_custom_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  producers: Fixture.Producers = Channel.new(PRODUCERS)
  return keep(ctx, Fixture.build_custom(producers), producers)
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

  return BDD.keep(ctx, APP) do |request|
    ask = try JSON.decode(request, Ask)
    try make_folder(base)
    app = Bond.app() |> Bond.static("/files", "#{base}/root")
    response = ask_request(app, ask, 0, 10_000)
    Path.remove(base)
    ok(JSON.from(reply_of(response)))
  end
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
  return BDD.keep(ctx, APP) do |request|
    ask = try JSON.decode(request, Ask)
    response = ask_request(app, ask, ask.max_pieces, ask.timeout_ms)
    wait_for_producers(producers)
    ok(JSON.from(reply_of(response)))
  end
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

def over_socket(ctx: BDD.Context, method: String, path: String, body: String) -> BDD.Context
  port = JSON.int(BDD.get(ctx, PORT).unwrap!).unwrap!
  client = HTTP.client(HTTP.client_options()).unwrap!
  response = HTTP.request(client, method, "http://127.0.0.1:#{port}#{path}", body.bytes, [])
  HTTP.close_client(client)
  return BDD.set(ctx, REPLY, JSON.from(reply_of(response.unwrap!)))
end
