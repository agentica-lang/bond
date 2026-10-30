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
    And the body is the events:
      """
      data: one

      event: note
      data: two
      data: lines
      """

  Scenario: A 304 loses its stream
    When I send "GET" to "/events-304"
    Then the status is 304
    And the body is ""

  Scenario: A stream with a header the server would refuse is a plain 500
    When I send "GET" to "/events-bad-header"
    Then the status is 500
    And the body is "Internal Server Error"
