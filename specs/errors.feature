Feature: Errors
  A handler that gives `error(message)` makes a 500 with a fixed text. The message goes to stderr and never to the
  client. So does a handler or filter that stops with a runtime error (an index out of range, an `unwrap!` of an
  error): the request runs in a task of its own, and the crash of the task is the error. A response that the HTTP
  server would refuse is a 500 too, in process as over a socket, except that a 204 and a 304 lose their body.

  Background:
    Given the todo app

  Scenario: A handler error is a 500 without its message
    When I send "GET" to "/boom"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "content-type" is "text/plain; charset=utf-8"

  Scenario: A handler that crashes is a 500 and the app goes on
    When I send "GET" to "/crash"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "x-powered-by" is not set
    When I send "GET" to "/hello"
    Then the status is 200

  Scenario: A 500 does not keep the headers the before filters set (only the after filters add theirs)
    When I send "GET" to "/boom"
    Then the status is 500
    And the header "x-trace" is "c"

  Scenario: A before filter that gives an error is a 500
    When I send "GET" to "/filter-error"
    Then the status is 500
    And the body is "Internal Server Error"

  Scenario Outline: A response the HTTP server cannot send is a 500, a 204 or 304 loses its body (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>
    And the body is "<body>"

    Examples:
      | path                | status | body                  |
      | /not-modified       | 304    |                       |
      | /status-99          | 500    | Internal Server Error |
      | /content-length     | 500    | Internal Server Error |
      | /transfer-encoding  | 500    | Internal Server Error |
      | /location-non-ascii | 500    | Internal Server Error |
      | /location-newline   | 500    | Internal Server Error |
      | /header-bad-name    | 500    | Internal Server Error |
