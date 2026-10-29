Feature: Testing.request
  `Testing.request(app, method, target)` runs an app in process. The headers and the body are optional: they default
  to no headers and an empty body.

  Scenario: The headers and the body can be left out
    Given the Agentica program "fixtures/short_request.agc"
    Then the program exits with code 0 within 5000 milliseconds
    And stdout is:
      """
      hello none 0
      hello bond 0
      hello none 3

      """
