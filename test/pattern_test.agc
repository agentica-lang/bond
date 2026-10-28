import Pattern from "../src/pattern"

def main() -> Void
  Test.run([
    Test.test("a colon segment takes the text of its place, a literal segment must be equal") do
      try Test.eq(Pattern.matches("/users/:id/posts/:post", "/users/7/posts/42"), ok({"id": "7", "post": "42"}))
      try Test.error?(Pattern.matches("/users/:id", "/people/7"))
      try Test.error?(Pattern.matches("/users/:id", "/users"))
      Test.error?(Pattern.matches("/users", "/users/7"))
    end,
    Test.test("empty segments are ignored") do
      try Test.eq(Pattern.matches("/users/", "//users"), ok({}))
      Test.eq(Pattern.matches("/", ""), ok({}))
    end,
    Test.test("a pattern starts with a slash and names each param once") do
      try Test.assert(Pattern.valid?("/a/:b/:c"), "a good pattern")
      try Test.assert(not Pattern.valid?("a/b"), "no leading slash")
      try Test.assert(not Pattern.valid?("/a/:"), "a param without a name")
      Test.assert(not Pattern.valid?("/a/:id/b/:id"), "a name twice")
    end,
  ])
end
