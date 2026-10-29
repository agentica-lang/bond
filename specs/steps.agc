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

struct Ask
  method: String
  path: String
  headers: List[Header]
  body: String
end

struct Reply
  status: Int
  headers: Map[String, String]
  body: String
end

def main() -> Void
  BDD.run([
    BDD.step("the todo app", &keep_app),
    BDD.step("the todo app with custom handlers", &keep_custom_app),
    BDD.step("I send {string} to {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: ""))
    end,
    BDD.step("I send {string} to {string} with the body {string}") do |ctx, args|
      send(ctx, Ask(method: args[0], path: args[1], headers: [], body: args[2]))
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
    BDD.step("the status is {int}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.status == args[0].to_i!, "the status is #{reply.status}")
    end,
    BDD.step("the body is {string}") do |ctx, args|
      reply = last_reply(ctx)
      BDD.assert(ctx, reply.body == args[0], "the body is #{reply.body}")
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
  return keep(ctx, Fixture.build())
end

def keep_custom_app(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return keep(ctx, Fixture.build_custom())
end

def keep(ctx: BDD.Context, app: Bond.App) -> BDD.Context
  return BDD.keep(ctx, APP) do |request|
    ask = try JSON.decode(request, Ask)
    response = Testing.request(app, ask.method, ask.path, ask.headers, ask.body)
    ok(JSON.from(reply_of(response)))
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

def reply_of(response: HttpResponse) -> Reply
  start: Map[String, String] = {}
  fields = response.headers.reduce(start) do |acc, header| acc.put(header.name.downcase, header.value) end
  return Reply(status: response.status, headers: fields, body: response.body)
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
  response = HTTP.request(client, method, "http://127.0.0.1:#{port}#{path}", [], body)
  HTTP.close_client(client)
  return BDD.set(ctx, REPLY, JSON.from(reply_of(response.unwrap!)))
end
