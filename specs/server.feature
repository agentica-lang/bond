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

  Scenario: The client address of a request over a socket is the address of the peer
    Given the server listens on a free port
    When I get "/client" over the socket
    Then the status is 200
    And the body is "127.0.0.1"

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
    And the header "accept-ranges" is "bytes"

  Scenario: A static file over a socket has a validator, and a matching If-None-Match is a 304 with no body
    Given the server listens on a free port
    When I get "/assets/hello.txt" over the socket
    Then the header "etag" starts with "\""
    And the header "cache-control" is "no-cache"
    When I get "/assets/hello.txt" over the socket with the header "if-none-match" set to "*"
    Then the status is 304
    And the body is ""
    And the header "content-length" is not set
    When I get "/hello" over the socket
    Then the body is "hello"

  Scenario: A range of a file over a socket is a 206 that has the length of the part
    Given the server listens on a free port
    When I get "/assets/hello.txt" over the socket with the header "range" set to "bytes=6-9"
    Then the status is 206
    And the body is "from"
    And the header "content-length" is "4"
    And the header "content-range" is "bytes 6-9/17"
    When I get "/hello" over the socket
    Then the body is "hello"

  Scenario: A stream over a socket has the pieces and the channel closing ends the body
    Given the server listens on a free port
    When I get "/events" over the socket
    Then the status is 200
    And the header "content-type" is "text/event-stream; charset=utf-8"
    And the body is the text "data: one\\n\\nevent: note\\ndata: two\\ndata: lines\\n\\n"
    When I get "/hello" over the socket
    Then the body is "hello"

  Scenario Outline: A chunked body that is refused after the app could have started never reaches it (<case>)
    Given the server with a small body limit listens on a free port
    When I post the chunks "<chunks>" to "/todos" over a raw socket
    Then the status is <status>
    And the header "connection" is "close"
    And the body is ""
    When I get "/todos" over the socket
    Then the body is "[]"

    Examples:
      | case                     | chunks              | status |
      | two chunks over 8 bytes  | 5~aaaaa~5~bbbbb~0~~ | 413    |
      | a bad chunk size         | zz~aaaaa~0~~        | 400    |

  Scenario: A chunked body within the limit reaches the app and keeps the connection
    Given the server with a small body limit listens on a free port
    When I post the chunks "3~abc~0~~" to "/todos" over a raw socket
    Then the status is 201
    And the header "connection" is not set
    When I get "/todos" over the socket
    Then the body is "[{\"id\":1,\"title\":\"abc\"}]"
