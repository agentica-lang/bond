import Dates from "../src/dates"

def main() -> Void
  Test.run([
    Test.test("a date is written in the form of RFC 9110") do
      try Test.eq(Dates.format(784_111_777), "Sun, 06 Nov 1994 08:49:37 GMT")
      try Test.eq(Dates.format(0), "Thu, 01 Jan 1970 00:00:00 GMT")
      try Test.eq(Dates.format(1_700_000_000), "Tue, 14 Nov 2023 22:13:20 GMT")
      try Test.eq(Dates.format(951_782_400), "Tue, 29 Feb 2000 00:00:00 GMT")
      Test.eq(Dates.format(-5), "Thu, 01 Jan 1970 00:00:00 GMT")
    end,
    Test.test("what format writes, parse reads back") do
      for seconds in [0, 59, 86_399, 951_782_400, 1_700_000_000, 4_102_444_799, 4_107_542_400]
        try Test.eq(Dates.parse(Dates.format(seconds)), some(seconds))
      end

      Test.eq(Dates.parse("  Sun, 06 Nov 1994 08:49:37 GMT "), some(784_111_777))
    end,
    Test.test("a text that is not that form is not a date") do
      for text in [
        "", "yesterday", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994", "Sun, 06 Nov 1994 08:49:37 UTC",
        "Sun, 06 Xyz 1994 08:49:37 GMT", "Sun, 06 Nov 1994 25:49:37 GMT", "Sun, 0a Nov 1994 08:49:37 GMT",
      ]
        try Test.eq(Dates.parse(text), none)
      end

      Test.eq(Dates.parse("Sun, 32 Nov 1994 08:49:37 GMT"), none)
    end,
  ])
end
