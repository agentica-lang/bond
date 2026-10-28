Feature: Todos
  The todo app keeps its state in an `ATS` table that its handlers reach through a closure. Each scenario is a new
  process, so each starts with no todos.

  Background:
    Given the todo app

  Scenario: Create a todo and read it back
    When I send "POST" to "/todos" with the body "buy milk"
    Then the status is 201
    And the header "content-type" is "application/json"
    And the JSON body is:
      """
      {"id": 1, "title": "buy milk"}
      """
    When I send "GET" to "/todos/1"
    Then the status is 200
    And the JSON body is:
      """
      {"id": 1, "title": "buy milk"}
      """

  Scenario: Todos get the next id each
    Given I send "POST" to "/todos" with the body "one"
    When I send "POST" to "/todos" with the body "two"
    Then the status is 201
    And the JSON body is:
      """
      {"id": 2, "title": "two"}
      """

  Scenario: A todo that does not exist is a 404 that stops the handler
    When I send "GET" to "/todos/99"
    Then the status is 404
    And the body is "not found"

  Scenario: An id that is not a number is a 400
    When I send "GET" to "/todos/abc"
    Then the status is 400
    And the body is "id must be an integer"
