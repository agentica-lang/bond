import Pattern from "../src/pattern"

def main() -> Void
  Test.run([
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
