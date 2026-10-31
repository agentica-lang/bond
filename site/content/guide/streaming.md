---
title: Streaming
weight: 12
description: Answer with a body that is sent piece by piece, such as server-sent events.
---

# Streaming

Most answers are whole: `Bond.text`, `Bond.json_as` and the others hold the body when the handler returns. For a body that is not ready yet (events, tokens as a model makes them, a big file) use `Bond.stream(conn, status, channel)`. The handler makes a `Channel[Bytes]`, starts a task that sends the pieces on it, and returns. The server sends the head at once and each piece as it comes, and the producer closing the channel ends the body.

`Bond.sse(conn, events)` is the same for server-sent events: a 200 with `Content-Type: text/event-stream; charset=utf-8` and `Cache-Control: no-cache`. `Bond.sse_event(data, event)` makes the `Bytes` of one event: an optional `event:` line, a `data:` line for each line of `data`, and the empty line that ends it. A line break in the name of the event is replaced by a space.

The producer must:

- close the channel on every path, or the response never ends;
- stop when `send` gives an error: the channel is closed when the client leaves, so its next `send` is `error("channel: closed")`;
- send with a timeout, so a client that stops reading cannot hold it for ever. A bounded channel is the back pressure.

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def produce(events: Channel[Bytes]) -> Void
  for n in 1..3
    if not events.send(Bond.sse_event("tick #{n}", "tick"), 5000).ok?
      break
    end
  end

  events.close
end

def ticks(conn: Bond.Conn) -> Result[Bond.Conn]
  events: Channel[Bytes] = Channel.new(8)
  Task.spawn(&produce, events)
  return ok(Bond.sse(conn, events))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/ticks", &ticks)
  response = Testing.request(app, "GET", "/ticks")
  puts(response.status)
  puts(response.headers.select do |header| header.name == "content-type" end[0].value)
  puts(Testing.text(response).unwrap!)
end
```

```output
200
text/event-stream; charset=utf-8
event: tick
data: tick 1

event: tick
data: tick 2

event: tick
data: tick 3

```

`Testing.request` reads the channel to its end, so a test sees all the events as one body (see [Testing](/guide/testing/) for `max_pieces` and `timeout_ms`, which cut a stream that never ends). Over the server, a browser's `EventSource` or `curl -N` sees each event when it is sent.

## A body with a known size

A stream has no `Content-Length`: the server sends chunks. When the size is known before the body is (a file), give it as the last argument: `Bond.stream(conn, 200, channel, some(size))`. The head then says `Content-Length: size` and the pieces go out as they are, with no chunks, so a client can show a progress bar and resume. The producer must send exactly `size` bytes: a body that ends short, or one that would go over, closes the connection, and the client sees an incomplete body. A `size` that is negative is a 500. [`Bond.send_file`](/guide/files/) does this for a file. `Testing.request` shows the `Content-Length` header of such a stream, since it has no socket.

## Rules

- A stream replaces the body set before it, and `Bond.text`, `html`, `json`, `json_as`, `redirect` and `halt` after it replace the stream (a `halt(conn, 403, ...)` after `sse` is a 403 with a text body). A channel that is replaced by a body helper is closed, so its producer stops; `Bond.stream` does not close the one it replaces, so a filter can wrap a stream (read `conn.response_stream`, pump it into a new channel, call `Bond.stream`) and then closing the old channel is up to it. Set other headers with `Bond.header`. `Content-Length` and `Transfer-Encoding` are the server's, so setting them is a 500 (and the channel is closed).
- A 204 or a 304 has no body, so its channel is closed and nothing is sent. `HEAD` gets the head only.
- A stream that is not sent (an `error` of an `after` filter, a response the server refuses) is closed, so its producer stops. A crash (a runtime error) in an `after` filter does not close it: Bond does not know the channel then, so the producer must send with a timeout, as above, and stop when it ends.
- A failure after the head went out cannot change the status: the body is cut and the client sees it as incomplete. Check what can fail before you return the stream.
- Filters and routes run as for any answer, before the stream starts; the `after` filters run when the handler returns, not when the stream ends.
- The `Conn` of the handler is gone once it returns, so the producer gets what it needs through its arguments (the channel, and any data it reads), not the `Conn`.
