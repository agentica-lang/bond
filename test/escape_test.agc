import Conns from "../src/conn"

def main() -> Void
  Test.run([
    Test.test("escape replaces the five characters of HTML") do
      Test.eq(Conns.escape("<a href=\"x\" t='y'>&</a>"), "&lt;a href=&quot;x&quot; t=&#39;y&#39;&gt;&amp;&lt;/a&gt;")
    end,
    Test.test("escape runs once: an entity in the text is escaped, not kept") do
      Test.eq(Conns.escape("&lt;"), "&amp;lt;")
    end,
    Test.test("escape leaves plain text and the empty text as they are") do
      try Test.eq(Conns.escape("Ana Maria, 42!"), "Ana Maria, 42!")
      Test.eq(Conns.escape(""), "")
    end,
  ])
end
