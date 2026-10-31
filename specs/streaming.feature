Feature: Streamed bodies
  `Bond.stream` and `Bond.sse` answer with the pieces that a task sends on a channel. `Testing.request` reads the
  channel to its end and gives the pieces as the body. The server sends them as they come
  (a scenario of `server.feature` runs it over a socket).

  Background:
    Given the todo app

  Scenario: Server-sent events are the pieces in order with the event stream headers
    When I send "GET" to "/events"
    Then the status is 200
    And the header "content-type" is "text/event-stream; charset=utf-8"
    And the header "cache-control" is "no-cache"
    And the header "x-powered-by" is "bond"
    And the body is the text "data: one\\n\\nevent: note\\ndata: two\\ndata: lines\\n\\n"

  Scenario: A 304 loses its stream
    When I send "GET" to "/events-304"
    Then the status is 304
    And the body is ""

  Scenario: A stream with a header the server would refuse is a plain 500
    When I send "GET" to "/events-bad-header"
    Then the status is 500
    And the body is "Internal Server Error"

  Scenario: A body helper after a stream replaces it
    When I send "GET" to "/events-replaced"
    Then the status is 403
    And the body is "forbidden"
    And the header "content-type" is "text/plain; charset=utf-8"

  Scenario: A HEAD request gets no body
    When I send "HEAD" to "/events"
    Then the status is 200
    And the body is ""

  Scenario: A stream that never ends is cut after the pieces asked for, and its producer stops
    When I send "GET" to "/endless" keeping at most 3 pieces
    Then the status is 200
    And the body is the text "data: tick\\n\\ndata: tick\\n\\ndata: tick\\n\\n"
    When I send "GET" to "/endless-stopped"
    Then the body is "stopped"

  Scenario: A stream that never ends is cut at the time limit, and its producer stops
    When I send "GET" to "/endless" waiting at most 300 ms
    Then the status is 200
    And the header "content-type" is "text/event-stream; charset=utf-8"
    When I send "GET" to "/endless-stopped"
    Then the body is "stopped"

  Scenario: A stream that is not UTF-8 text is read as bytes
    When I send "GET" to "/events-binary"
    Then the status is 200
    And the body bytes are "255 216 0"
