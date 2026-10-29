Feature: Custom handlers
  `Bond.not_found` replaces the 404 answer of a path with no route, and `Bond.on_error` the 500 answer of a failure
  (an `error` or a runtime error in a handler or filter). The error handler gets the message of the failure, which
  is for logging: the client sees only what the handler answers. A handler that fails itself gives the plain 500.
  The app of `build_custom` in `specs/fixtures/app.agc` has both.

  Background:
    Given the todo app with custom handlers

  Scenario: The not found handler answers a path with no route
    When I send "GET" to "/nothing"
    Then the status is 404
    And the body is "<h1>No page at /nothing</h1>"
    And the header "content-type" is "text/html; charset=utf-8"

  Scenario: The after filters still run for the not found handler
    When I send "GET" to "/nothing"
    Then the header "x-powered-by" is "bond"

  Scenario: A path with a route for other methods is still a 405
    When I send "POST" to "/hello"
    Then the status is 405
    And the body is "method not allowed"

  Scenario Outline: The error handler answers a failure (<path>)
    When I send "GET" to "<path>"
    Then the status is 500
    And the body is "Something went wrong"
    And the header "content-type" is "text/html; charset=utf-8"

    Examples:
      | path |
      | /boom |
      | /crash |

  Scenario: The error handler gets the message of the failure
    When I send "GET" to "/boom"
    Then the header "x-error" is "secret details"

  Scenario: A not found handler that fails is a failure for the error handler
    When I send "GET" to "/nothing-bad"
    Then the status is 500
    And the body is "Something went wrong"
    And the header "x-error" is "the not found handler failed"

  Scenario Outline: A failure of the error handler is the plain 500 (<path>)
    When I send "GET" to "<path>"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "content-type" is "text/plain; charset=utf-8"

    Examples:
      | path |
      | /filter-error |
      | /boom-again |

  Scenario: A bad request is a 400 and not for the error handler
    When I send "POST" to "/todos"
    Then the status is 400
    And the body is "title is empty"

  Scenario: The not found handler answers a missing static file
    When I send "GET" to "/assets/missing.txt"
    Then the status is 404
    And the body is "<h1>No page at /assets/missing.txt</h1>"

  Scenario: A static file that cannot be sent goes to the error handler
    When I send "GET" to "/assets/bad.txt"
    Then the status is 500
    And the body is "Something went wrong"
    And the header "x-error" is "the static file bad.txt is not valid UTF-8 text or could not be read"
