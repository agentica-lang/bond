Feature: Assigns
  `Bond.assign(conn, key, value)` keeps a value in the `Conn` for the filters and the handler that come after it, and
  `Bond.assigned(conn, key, codec)` reads it back as a `Result` of the type of the codec. A filter that loaded the
  signed-in person assigns them once, and the handler does not load them again. The values are never sent to the
  client. The routes of `Fixture.build_assigns` in `specs/fixtures/app.agc` use it.

  Scenario: The handler reads the struct that the filter assigned, with the same type
    Given the assigns app
    When I send "GET" to "/me" with the header "x-user" set to "ana"
    Then the body is "7 ana ana@example.com"

  Scenario: A key that nothing assigned is an error, not a value
    Given the assigns app
    When I send "GET" to "/nobody" with the header "x-user" set to "ana"
    Then the body is "refused=true assigned=false"

  Scenario: A value read as another type is an error
    Given the assigns app
    When I send "GET" to "/as-team" with the header "x-user" set to "ana"
    Then the body is "refused=true assigned=true"

  Scenario: A handler that needs the person, when no filter assigned one, answers a 500
    Given the assigns app
    When I send "GET" to "/me"
    Then the status is 500
    And the body is "Internal Server Error"

  Scenario: A filter after the one that assigned sees the value
    Given the assigns app
    When I send "GET" to "/me" with the header "x-user" set to "ana"
    Then the header "x-seen" is "ana"
