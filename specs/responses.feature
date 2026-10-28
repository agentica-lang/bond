Feature: Responses
  `Bond.html`, `Bond.status` and `Bond.redirect` build the answer. `Bond.html` does not escape the text; HTML
  escaping is not in Bond yet. A redirect halts, so a `before` filter can use it.

  Background:
    Given the todo app

  Scenario: Answer HTML
    When I send "GET" to "/page"
    Then the status is 200
    And the body is "<p>hi</p>"
    And the header "content-type" is "text/html; charset=utf-8"

  Scenario: Set only the status
    When I send "GET" to "/accepted"
    Then the status is 202
    And the body is ""

  Scenario: A redirect is a 302 with a Location header and no body
    When I send "GET" to "/redirect"
    Then the status is 302
    And the header "location" is "/hello"
    And the body is ""

  Scenario Outline: A redirect takes the status of the redirect (<status>)
    When I send "GET" to "/redirect/<status>"
    Then the status is <answer>
    And the header "location" is "<location>"

    Examples:
      | status | answer | location |
      | 301    | 301    | /hello   |
      | 303    | 303    | /hello   |
      | 307    | 307    | /hello   |
      | 308    | 308    | /hello   |
      | 200    | 500    |          |

  Scenario: A redirect in a before filter stops the handler
    When I send "GET" to "/legacy"
    Then the status is 302
    And the header "location" is "/hello"
    And the header "x-powered-by" is "bond"
