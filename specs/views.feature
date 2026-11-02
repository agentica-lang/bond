Feature: Views
  A view is a function that returns a String, written as an EAG template that starts with `<%@ escape &Bond.escape %>`.
  A page is a function that renders partials, and a layout is a function that takes the inner HTML. The inner HTML is
  already escaped, so the layout inserts it with `<%== %>`. The app of `specs/fixtures/app.agc` has `/room`, a page
  with a partial for each comment, in a layout, and `Bond.html` sends the result.

  Scenario: A page renders its partials inside the layout
    Given the todo app
    When I send "GET" to "/room?name=Lobby"
    Then the status is 200
    And the header "content-type" is "text/html; charset=utf-8"
    And the body is the text "<title>Lobby</title>\\n<main>\\n<h1>Lobby</h1>\\n<ul>\\n<li class='comment'><b>Ana</b>: hello</li>\\n<li class='comment'><b>Lobby</b>: Lobby</li>\\n</ul>\\n</main>\\n"

  Scenario: A hostile value is escaped in the layout, the page and the partial, and the inner HTML is not escaped twice
    Given the todo app
    When I send "GET" to "/room?name=%3Cscript%3Ex%3C%2Fscript%3E+%27a%27+%26"
    Then the status is 200
    And the body is the text "<title>&lt;script&gt;x&lt;/script&gt; &#39;a&#39; &amp;</title>\\n<main>\\n<h1>&lt;script&gt;x&lt;/script&gt; &#39;a&#39; &amp;</h1>\\n<ul>\\n<li class='comment'><b>Ana</b>: hello</li>\\n<li class='comment'><b>&lt;script&gt;x&lt;/script&gt; &#39;a&#39; &amp;</b>: &lt;script&gt;x&lt;/script&gt; &#39;a&#39; &amp;</li>\\n</ul>\\n</main>\\n"
