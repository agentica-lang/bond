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
