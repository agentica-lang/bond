Feature: Routing
  A route is a method and a path pattern. A segment that starts with a colon, as in `/users/:id`, matches any one
  segment and gives its text as a param. The routes are tried in the order they were added. The todo app of
  `specs/fixtures/app.agc` has the routes.

  Background:
    Given the todo app

  Scenario: A route answers its path
    When I send "GET" to "/hello"
    Then the status is 200
    And the body is "hello"
    And the header "content-type" is "text/plain; charset=utf-8"

  Scenario: A trailing slash does not change the route
    When I send "GET" to "/hello/"
    Then the status is 200
    And the body is "hello"

  Scenario: A colon segment gives a param
    When I send "GET" to "/users/7/posts/42"
    Then the status is 200
    And the body is "user 7, post 42"

  Scenario: A route added first wins over a pattern that also matches
    When I send "GET" to "/todos/latest"
    Then the status is 200
    And the body is "the latest todo"

  Scenario: A path with no route is a 404
    When I send "GET" to "/nothing"
    Then the status is 404
    And the body is "not found"

  Scenario Outline: A path with a route for other methods is a 405 that lists them (<method> <path>)
    When I send "<method>" to "<path>"
    Then the status is 405
    And the header "allow" is "<allow>"

    Examples:
      | method | path   | allow     |
      | POST   | /hello | GET       |
      | DELETE | /todos | GET, POST |
