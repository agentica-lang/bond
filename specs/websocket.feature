Feature: WebSocket routes
  `Bond.websocket` adds a route whose handshake is upgraded on the server of the app, so a page, a stream and a
  WebSocket share one port. The program of `specs/fixtures/websocket_server.agc` listens on 127.0.0.1 and a free port;
  the steps speak the WebSocket protocol by hand over a socket. The framing itself (masks, fragments, pings) is the
  contract of `std/http`: the client masks every frame, so the echo proves the unmasking, and nothing more is checked
  here.

  Scenario: A page, a stream and a WebSocket on one port, and the WebSocket echoes with the param of the route
    Given the WebSocket server listens on a free port
    When I get "/hello" over the socket
    Then the body is "hello"
    When I get "/ticks" over the socket
    Then the body is "one two"
    When I open a WebSocket to "/chat/lobby" from the origin "http://127.0.0.1:PORT" and send "hi"
    Then the status is 101
    And the header "sec-websocket-accept" is "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    And the WebSocket answers "lobby: hi"
    And the WebSocket closes with the code 1000

  Scenario Outline: The origin of a handshake decides (<case>)
    Given the WebSocket server listens on a free port
    When I open a WebSocket to "/chat/lobby" from the origin "<origin>" and send "hi"
    Then the status is <status>

    Examples:
      | case                      | origin                  | status |
      | a page of this server     | http://127.0.0.1:PORT   | 101    |
      | an allowed origin         | https://app.example.com | 101    |
      | another site              | https://evil.test       | 403    |
      | this host on another port | http://127.0.0.1:1      | 403    |
      | the null origin           | null                    | 403    |

  Scenario: A handshake with no origin is not from a browser and is upgraded
    Given the WebSocket server listens on a free port
    When I open a WebSocket to "/chat/lobby" with no origin and send "hi"
    Then the status is 101
    And the WebSocket answers "lobby: hi"

  Scenario: A client that leaves without a close frame ends the handler with code 1006
    Given the WebSocket server listens on a free port
    When I open a WebSocket to "/chat/gone" with no origin, send "hi" and leave
    Then the status is 101
    And the WebSocket answers "gone: hi"
    And the server prints "closed gone 1006"

  Scenario: Two Origin headers are refused, even when one is this server
    Given the WebSocket server listens on a free port
    When I open a WebSocket to "/chat/lobby" from the origins "http://127.0.0.1:PORT" and "https://app.example.com" and send "hi"
    Then the status is 403

  Scenario: A request that does not ask for the upgrade is a 426
    Given the WebSocket server listens on a free port
    When I get "/chat/lobby" over the socket
    Then the status is 426
    And the header "upgrade" is "websocket"
    And the body is "upgrade required"

  Scenario: A handler that crashes closes its WebSocket with 1011 and the server goes on
    Given the WebSocket server listens on a free port
    When I open a WebSocket to "/chat/lobby" with no origin and send "crash"
    Then the status is 101
    And the WebSocket closes with the code 1011
    When I get "/hello" over the socket
    Then the body is "hello"
