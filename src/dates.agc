## The date of `Last-Modified` and `If-Modified-Since` (RFC 9110 section 5.6.7), as Unix seconds.

SECONDS_PER_DAY = 86_400

# Day 0 of the Unix epoch was a Thursday.
WEEKDAYS = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"]

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

MONTH_NUMBERS = {
  "Jan": 1,
  "Feb": 2,
  "Mar": 3,
  "Apr": 4,
  "May": 5,
  "Jun": 6,
  "Jul": 7,
  "Aug": 8,
  "Sep": 9,
  "Oct": 10,
  "Nov": 11,
  "Dec": 12,
}

# The days from 0000-03-01 to 1970-01-01, the shift of the civil calendar algorithms below.
EPOCH_SHIFT = 719_468

DAYS_PER_ERA = 146_097

## `Sun, 06 Nov 1994 08:49:37 GMT` for the Unix time `seconds`. A time before 1970 is written as 1970.
export def format(seconds: Int) -> String
  clamped = seconds
  if clamped < 0
    clamped = 0
  end

  days = clamped / SECONDS_PER_DAY
  rest = clamped - days * SECONDS_PER_DAY
  z = days + EPOCH_SHIFT
  era = z / DAYS_PER_ERA
  day_of_era = z - era * DAYS_PER_ERA
  year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365
  day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  shifted_month = (5 * day_of_year + 2) / 153
  day = day_of_year - (153 * shifted_month + 2) / 5 + 1
  month = shifted_month + 3
  year = year_of_era + era * 400
  if shifted_month >= 10
    month = shifted_month - 9
    year = year + 1
  end

  clock = "#{two(rest / 3600)}:#{two(rest % 3600 / 60)}:#{two(rest % 60)}"
  return "#{WEEKDAYS[days % 7]}, #{two(day)} #{MONTHS[month - 1]} #{year} #{clock} GMT"
end

## The Unix seconds of a date in one of the three forms that a recipient reads (RFC 9110 section 5.6.7): the one
## `format` writes (`Sun, 06 Nov 1994 08:49:37 GMT`), the old `Sunday, 06-Nov-94 08:49:37 GMT` (a year of two digits is
## 1970 to 1999 from 70, and 2000 to 2069 below it) and `Sun Nov  6 08:49:37 1994`. Any other text is `none`, and a
## header with one is ignored. The name of the weekday is not checked.
export def parse(text: String) -> Optional[Int]
  parts = text.strip.replace("  ", " ").split(" ")
  if parts.size == 6 and parts[5] == "GMT" and parts[0].end_with?(",")
    return assemble(parts[1], parts[2], parts[3], parts[4])
  end

  if parts.size == 4 and parts[3] == "GMT" and parts[0].end_with?(",")
    pieces = parts[1].split("-")
    if pieces.size == 3
      return assemble(pieces[0], pieces[1], pieces[2], parts[2])
    end
  end

  if parts.size == 5 and not parts[0].end_with?(",")
    return assemble(parts[2], parts[1], parts[4], parts[3])
  end

  return none
end

# The seconds of the date made of the text of its parts, or `none` when one is not what it must be.
def assemble(day_text: String, month_text: String, year_text: String, clock_text: String) -> Optional[Int]
  clock = clock_text.split(":")
  month = MONTH_NUMBERS.get(month_text, 0)
  if clock.size != 3 or month == 0
    return none
  end

  numbers = [day_text, year_text, clock[0], clock[1], clock[2]].map do |part| number(part) end
  if numbers.any? do |n| n < 0 end
    return none
  end

  day = numbers[0]
  year = numbers[1]
  hour = numbers[2]
  if year_text.length == 2
    year = year + two_digit_century(year)
  end

  if year_text.length != 2 and year_text.length != 4
    return none
  end

  if day < 1 or day > 31 or hour > 23 or numbers[3] > 59 or numbers[4] > 60
    return none
  end

  days = days_since_epoch(year, month, day)
  return some(days * SECONDS_PER_DAY + hour * 3600 + numbers[3] * 60 + numbers[4])
end

# What to add to a year of two digits: 1900 from 70, 2000 below it.
def two_digit_century(year: Int) -> Int
  if year >= 70
    return 1900
  end

  return 2000
end

# The civil date as days since 1970-01-01 (the proleptic Gregorian calendar).
def days_since_epoch(year: Int, month: Int, day: Int) -> Int
  shifted_year = year
  if month <= 2
    shifted_year = year - 1
  end

  era = shifted_year / 400
  year_of_era = shifted_year - era * 400
  day_of_year = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
  day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
  return era * DAYS_PER_ERA + day_of_era - EPOCH_SHIFT
end

# The digits of `text` as a number, or -1 when it is not only digits.
def number(text: String) -> Int
  if text.empty? or not text.split("").all? do |ch| ch.code >= 48 and ch.code <= 57 end
    return -1
  end

  return text.to_i!
end

def two(n: Int) -> String
  if n < 10
    return "0#{n}"
  end

  return n.to_s
end
