Feature: Cookie sessions
  `Bond.sessions(app, options)` keeps a small session in a signed cookie (HMAC-SHA256: the client can read it, not
  change it). `Bond.session(conn)` is the session as a map, `Bond.get_session` reads one value (an error when it is not
  there), `Bond.set_session`, `Bond.delete_session` and `Bond.clear_session` change it, and the answer carries the new
  cookie with `Path=/`, `Max-Age`, `HttpOnly` and `SameSite=Lax` (and `Secure` when the options ask for it). A cookie that
  is missing, changed, expired or signed with an unknown secret is an empty session. A request that does not change the
  session sets no cookie. The routes of `Fixture.build_sessions` in `specs/fixtures/app.agc` use it.

  Scenario: A visitor with no session has an empty one
    Given the sessions app
    When I send "GET" to "/me"
    Then the body is "user=nobody values=0"
    And the header "set-cookie" is not set

  Scenario: A value set by a route is there in the next request
    Given the sessions app
    When I send "GET" to "/login/ana"
    Then the body is "welcome"
    When I send "GET" to "/me" with the session cookie of the last answer
    Then the body is "user=ana values=1"

  Scenario: The cookie has the flags of a session
    Given the sessions app
    When I send "GET" to "/login/ana"
    Then the header "set-cookie" appears 1 times
    And the header "set-cookie" starts with "_bond_session="
    And the header "set-cookie" ends with "; Path=/; Max-Age=1209600; HttpOnly; SameSite=Lax"

  Scenario: A session counts across requests
    Given the sessions app
    When I send "GET" to "/visits"
    Then the body is "visits=1"
    When I send "GET" to "/visits" with the session cookie of the last answer
    Then the body is "visits=2"

  Scenario: A request that changes nothing sets no cookie
    Given the sessions app
    When I send "GET" to "/login/ana"
    And I send "GET" to "/peek" with the session cookie of the last answer
    Then the body is "user=ana values=1"
    And the header "set-cookie" is not set

  Scenario: A value is deleted and the cookie is written again
    Given the sessions app
    When I send "GET" to "/login/ana"
    And I send "GET" to "/forget" with the session cookie of the last answer
    Then the header "set-cookie" appears 1 times
    When I send "GET" to "/me" with the session cookie of the last answer
    Then the body is "user=nobody values=0"

  Scenario: Clearing the session deletes the cookie
    Given the sessions app
    When I send "GET" to "/login/ana"
    And I send "GET" to "/logout" with the session cookie of the last answer
    Then the header "set-cookie" has the value "_bond_session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"

  Scenario: A cookie that was changed is an empty session
    Given the sessions app
    When I send "GET" to "/login/ana"
    And I send "GET" to "/me" with the session cookie of the last answer changed
    Then the body is "user=nobody values=0"

  Scenario: A cookie that is not signed or has expired is an empty session
    Given the sessions app
    When I send "GET" to "/me" with the cookie "_bond_session=bm9wZQ.bm9wZQ"
    Then the body is "user=nobody values=0"
    When I send "GET" to "/me" with an expired session for the user "ana"
    Then the body is "user=nobody values=0"

  Scenario: A cookie signed under another cookie name is not accepted
    Given the sessions app
    When I send "GET" to "/me" with a session signed for another cookie name for the user "ana"
    Then the body is "user=nobody values=0"

  Scenario: A session signed with the secret before a rotation is read and signed again
    Given the sessions app after the secret was rotated
    When I send "GET" to "/peek" with a session signed with the first secret for the user "ana"
    Then the body is "user=ana values=1"
    And the header "set-cookie" appears 1 times

  Scenario: A cookie signed with the new secret is not trusted by an app that does not know it
    Given the sessions app after the secret was rotated
    When I send "GET" to "/login/ana"
    Given the sessions app
    When I send "GET" to "/me" with the session cookie of the last answer
    Then the body is "user=nobody values=0"

  Scenario: A session too big for a cookie is a failure
    Given the sessions app
    When I send "GET" to "/blob"
    Then the status is 500
