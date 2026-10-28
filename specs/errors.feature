Feature: Errors
  A handler that gives `error(message)` makes a 500 with a fixed text. The message goes to stderr and never to the
  client.

  Background:
    Given the todo app

  Scenario: A handler error is a 500 without its message
    When I send "GET" to "/boom"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "content-type" is "text/plain; charset=utf-8"
