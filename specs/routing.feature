Feature: Routing
  A route is a method and a path pattern. A segment that starts with a colon, as in `/users/:id`, matches any one
  segment and gives its text as a param. The routes make a tree of segments: a literal segment wins over a param
  at the same place, whatever the order the routes were added in, and the walk goes back to the param when the literal
  branch has no route deeper. The method is chosen after the path. The todo app of `specs/fixtures/app.agc` has the
  routes.

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

  Scenario: A literal segment wins over a param that was added before it
    When I send "GET" to "/things/new"
    Then the status is 200
    And the body is "a new thing"

  Scenario: Another value takes the param
    When I send "GET" to "/things/7"
    Then the status is 200
    And the body is "thing 7"

  Scenario: A literal segment wins over a param that was added after it
    When I send "GET" to "/todos/latest"
    Then the status is 200
    And the body is "the latest todo"

  Scenario Outline: The walk goes back to the param when the literal branch has no route (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the body is "<body>"

    Examples:
      | path              | body       |
      | /docs/guide/intro | the intro  |
      | /docs/guide/edit  | edit guide |
      | /docs/api/edit    | edit api   |

  Scenario Outline: A path that no branch holds to the end is a 404 (<path>)
    When I send "GET" to "<path>"
    Then the status is 404

    Examples:
      | path              |
      | /docs/guide       |
      | /docs/guide/other |
      | /things/7/more    |

  Scenario Outline: Empty segments are ignored (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the body is "user 7, post 42"

    Examples:
      | path                  |
      | /users/7/posts/42/    |
      | //users//7///posts/42 |

  Scenario Outline: A route and a path are compared as written, without decoding (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>

    Examples:
      | path       | status |
      | /café      | 200    |
      | /caf%C3%A9 | 404    |

  Scenario: HEAD uses the route of GET
    When I send "HEAD" to "/hello"
    Then the status is 200

  Scenario: A path with no route is a 404
    When I send "GET" to "/nothing"
    Then the status is 404
    And the body is "not found"

  Scenario Outline: A path with a route for other methods is a 405 that lists them (<method> <path>)
    When I send "<method>" to "<path>"
    Then the status is 405
    And the header "allow" is "<allow>"

    Examples:
      | method  | path   | allow           |
      | POST    | /hello | GET, HEAD       |
      | DELETE  | /todos | GET, HEAD, POST |
      | OPTIONS | /hello | GET, HEAD       |

  Scenario Outline: The method is chosen after the path, so a literal route keeps its own methods (<method> <path>)
    When I send "<method>" to "<path>"
    Then the status is <status>

    Examples:
      | method | path        | status |
      | POST   | /things/7   | 200    |
      | POST   | /things/new | 405    |
      | HEAD   | /things/new | 200    |

  Scenario: The Allow header of a route comes from its own node
    When I send "DELETE" to "/things/new"
    Then the status is 405
    And the header "allow" is "GET, HEAD"

  Scenario Outline: A route that cannot be told from another stops the program when the app is built (<program>)
    Given the Agentica program "fixtures/<program>.agc"
    Then the program exits with code 1 within 5000 milliseconds

    Examples:
      | program            |
      | duplicate_route    |
      | duplicate_trailing |
      | param_names        |

  Scenario: The same pattern with another method, and the same param name, are not a conflict
    Given the Agentica program "fixtures/same_param.agc"
    Then the program exits with code 0 within 5000 milliseconds

  Scenario: The root route answers the empty path and the slash
    When I send "GET" to "/"
    Then the status is 200
    And the body is "the root"

  Scenario: A param of a branch that the walk left is not set
    When I send "GET" to "/a/lit/c"
    Then the status is 200
    And the body is "x=lit y=absent"

  Scenario: HEAD on a route that has POST only is a 405 that lists POST
    When I send "HEAD" to "/only-post"
    Then the status is 405
    And the header "allow" is "POST"

  Scenario: Two apps made from one base do not see each other's routes
    Given the Agentica program "fixtures/shared_base.agc"
    Then the program exits with code 0 within 5000 milliseconds
    And stdout is:
      """
      a: 200 404
      b: 404 200

      """

  Scenario: A path of thousands of segments is a 404 at once
    Given the Agentica program "fixtures/long_path.agc"
    Then the program exits with code 0 within 5000 milliseconds
    And stdout is:
      """
      404 404

      """
