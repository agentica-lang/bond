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
    Test.test("the old forms are read too, and name the same time") do
      try Test.eq(Dates.parse("Sun Nov  6 08:49:37 1994"), some(784_111_777))
      try Test.eq(Dates.parse("Sun Nov 16 08:49:37 1994"), some(784_111_777 + 10 * 86_400))
      try Test.eq(Dates.parse("Tuesday, 14-Nov-23 22:13:20 GMT"), some(1_700_000_000))
      Test.eq(Dates.parse("Sunday, 06-Nov-94 08:49:37 UTC"), none)
    end,
    Test.test("a year of two digits is of this century unless that is more than 50 years ahead") do
      try Test.eq(Dates.full_year(94, 2026), 1994)
      try Test.eq(Dates.full_year(23, 2026), 2023)
      try Test.eq(Dates.full_year(76, 2026), 2076)
      try Test.eq(Dates.full_year(77, 2026), 1977)
      try Test.eq(Dates.full_year(0, 2026), 2000)
      try Test.eq(Dates.full_year(60, 2044), 2060)
      Test.eq(Dates.full_year(96, 2044), 1996)
    end,
    Test.test("a text that is none of the forms is not a date") do
      for text in [
        "", "yesterday", "Sun Nov  6 08:49:37 94 x", "Sun, 06 Nov 94x 08:49:37 GMT", "Sun, 06 Nov 1994 08:49:37 UTC",
        "Sun, 06 Xyz 1994 08:49:37 GMT", "Sun, 06 Nov 1994 25:49:37 GMT", "Sun, 0a Nov 1994 08:49:37 GMT",
      ]
        try Test.eq(Dates.parse(text), none)
      end

      Test.eq(Dates.parse("Sun, 32 Nov 1994 08:49:37 GMT"), none)
    end,
  ])
end
