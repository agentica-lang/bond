## Server-sent events. Run it with `agentica examples/sse.agc` and try `curl -N http://127.0.0.1:4568/events`: each
## event shows when it is sent, one a second, then the stream ends.

import Bond from "../bond"

PORT = 4568

def produce(events: Channel[Bytes]) -> Void
  for n in 1..5
    if not events.send(Bond.sse_event("tick #{n}", "tick"), 5000).ok?
      break
    end

    Task.sleep(1000)
  end

  events.close
end

def events(conn: Bond.Conn) -> Result[Bond.Conn]
  channel: Channel[Bytes] = Channel.new(8)
  Task.spawn(&produce, channel)
  return ok(Bond.sse(conn, channel))
end

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/events", &events)
  )
  Bond.run(app, "127.0.0.1", PORT).unwrap!
end
