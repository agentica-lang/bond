import Pattern from "../src/pattern"

private

def main() -> Void
  Test.run([
    Test.test("empty segments are ignored") do
      try Test.eq(Pattern.segments("//users//7/"), ["users", "7"])
      Test.eq(Pattern.segments("/"), [])
    end,
    Test.test("a pattern starts with a slash and names each param once") do
      try Test.assert(Pattern.valid?("/a/:b/:c"), "a good pattern")
      try Test.assert(not Pattern.valid?("a/b"), "no leading slash")
      try Test.assert(not Pattern.valid?("/a/:"), "a param without a name")
      Test.assert(not Pattern.valid?("/a/:id/b/:id"), "a name twice")
    end,
    Test.test("the canonical path has one spelling for a name") do
      try Test.eq(Pattern.canonical("//a/%73%2e/"), "/a/s.")
      try Test.eq(Pattern.canonical("/%c3%A9/%2f/%/%4/%c3/%0a/%3a"), "/é/%2F/%/%4/%C3/%0A/%3A")
      Test.eq(Pattern.canonical(""), "/")
    end,
  ])
end
