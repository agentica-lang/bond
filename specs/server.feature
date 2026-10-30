Feature: Server
  `Bond.run` serves the app with the HTTP server of `std/http`. This is the only feature that opens a socket: the
  program of `specs/fixtures/server.agc` listens on 127.0.0.1 and a free port, and says which.

  Scenario: A request with a body over a real socket
    Given the server listens on a free port
    When I post "buy milk" to "/todos" over the socket
    Then the status is 201
    And the JSON body is:
      """
      {"id": 1, "title": "buy milk"}
      """

  Scenario: A handler that crashes is a 500 over a socket and the server goes on
    Given the server listens on a free port
    When I get "/crash" over the socket
    Then the status is 500
    And the body is "Internal Server Error"
    When I get "/hello" over the socket
    Then the status is 200
    And the body is "hello"

  Scenario Outline: The server options of `Bond.start_with` apply (a body of <size>)
    Given the server with a small body limit listens on a free port
    When I post "<body>" to "/todos" over the socket
    Then the status is <status>

    Examples:
      | size              | body              | status |
      | 4 bytes           | milk              | 201    |
      | more than 8 bytes | buy a lot of milk | 413    |

  Scenario: Each Set-Cookie is a header of its own over a socket
    Given the server listens on a free port
    When I get "/login" over the socket
    Then the header "set-cookie" appears 3 times
    And the header "set-cookie" has the value "sid=abc123; Path=/; HttpOnly; SameSite=Lax"

  Scenario: A static file over a socket has its length and its headers
    Given the server listens on a free port
    When I get "/assets/hello.txt" over the socket
    Then the status is 200
    And the body is "hello from a file"
    And the header "content-length" is "17"
    And the header "content-type" is "text/plain; charset=utf-8"
    And the header "x-content-type-options" is "nosniff"

  Scenario: A stream over a socket has the pieces and the channel closing ends the body
    Given the server listens on a free port
    When I get "/events" over the socket
    Then the status is 200
    And the header "content-type" is "text/event-stream; charset=utf-8"
    And the body is the text "data: one\\n\\nevent: note\\ndata: two\\ndata: lines\\n\\n"
    When I get "/hello" over the socket
    Then the body is "hello"
