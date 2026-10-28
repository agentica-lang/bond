Feature: Filters
  A `before` filter runs before the route, an `after` filter after it. Both are `Fn[Conn, Result[Conn]]`. A filter
  that halts stops the filters and the handler that come after it, but the `after` filters still run. A filter
  that gives an error is a 500.

  Background:
    Given the todo app

  Scenario: A before filter that halts stops the handler
    When I send "GET" to "/private"
    Then the status is 401
    And the body is "unauthorized"

  Scenario: A before filter can let the request through
    When I send "GET" to "/private" with the header "x-token" set to "letmein"
    Then the status is 200
    And the body is "secret page"

  Scenario Outline: An after filter adds a header to every answer (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>
    And the header "x-powered-by" is "bond"

    Examples:
      | path     | status |
      | /hello   | 200    |
      | /private | 401    |
      | /nothing | 404    |
      | /boom    | 500    |
