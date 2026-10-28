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

  Scenario: A redirect is a 302 with a Location header, no body and no content type
    When I send "GET" to "/redirect"
    Then the status is 302
    And the header "location" is "/hello"
    And the header "content-type" is not set
    And the body is ""

  Scenario Outline: A redirect takes the status of the redirect (<status>)
    When I send "GET" to "/redirect/<status>"
    Then the status is <status>
    And the header "location" is "/hello"

    Examples:
      | status |
      | 301    |
      | 303    |
      | 307    |
      | 308    |

  Scenario: A status that is not a redirect is a 500
    When I send "GET" to "/redirect/200"
    Then the status is 500
    And the header "location" is not set

  Scenario: A redirect in a before filter stops the handler
    When I send "GET" to "/legacy"
    Then the status is 302
    And the header "location" is "/hello"
    And the header "x-powered-by" is "bond"
