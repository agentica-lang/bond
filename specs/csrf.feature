Feature: Cross-site request protection
  `Bond.csrf(app)` refuses an unsafe request (any method but `GET`, `HEAD` and `OPTIONS`) that a page of another site
  sent, with a 403, and needs no token in the forms. A browser says where a request comes from: with `Sec-Fetch-Site`,
  only `same-origin` and `none` pass; with only an `Origin`, its host must be the `Host` of the request; with neither
  (`curl`, another server) it passes. `Bond.csrf(app, ["https://admin.example.net"])` lets the listed origins through.
  `GET /balance` and the methods of `/transfer` in `specs/fixtures/app.agc` show it. A header that is "" in a table
  is not sent.

  Scenario Outline: A POST is judged by where it comes from (<origin> <site> <host>)
    Given the app with CSRF protection
    When I send "POST" to "/transfer" with the origin "<origin>", the fetch site "<site>" and the host "<host>"
    Then the status is <status>

    Examples:
      | origin                   | site        | host        | status |
      |                          |             |             | 200    |
      | https://example.com      | same-origin | example.com | 200    |
      |                          | none        | example.com | 200    |
      | https://evil.test        | cross-site  | example.com | 403    |
      | https://blog.example.com | same-site   | example.com | 403    |
      |                          | cross-site  | example.com | 403    |
      | https://example.com      |             | example.com | 200    |
      | https://example.com:8443 |             | example.com | 403    |
      | https://EXAMPLE.com      |             | example.com | 200    |
      | https://evil.test        |             | example.com | 403    |
      | null                     |             | example.com | 403    |
      | https://example.com      |             |             | 403    |

  Scenario Outline: Every unsafe method is protected (<method>)
    Given the app with CSRF protection
    When I send "<method>" to "/transfer" with the origin "https://evil.test", the fetch site "cross-site" and the host "example.com"
    Then the status is 403
    And the body is "cross-origin request refused"

    Examples:
      | method |
      | POST   |
      | PUT    |
      | PATCH  |
      | DELETE |

  Scenario: A safe request from another site is not refused
    Given the app with CSRF protection
    When I send "GET" to "/balance" with the origin "https://evil.test", the fetch site "cross-site" and the host "example.com"
    Then the status is 200
    And the body is "balance 10"

  Scenario: A request from the same origin is answered by the route
    Given the app with CSRF protection
    When I send "DELETE" to "/transfer" with the origin "https://example.com", the fetch site "same-origin" and the host "example.com"
    Then the status is 200
    And the body is "transferred"

  Scenario Outline: A listed origin may call the app from another site (<origin>)
    Given the app with CSRF protection that allows https://admin.example.net
    When I send "POST" to "/transfer" with the origin "<origin>", the fetch site "cross-site" and the host "example.com"
    Then the status is <status>

    Examples:
      | origin                    | status |
      | https://admin.example.net | 200    |
      | https://ADMIN.example.net | 200    |
      | https://evil.test         | 403    |
      | http://admin.example.net  | 403    |
