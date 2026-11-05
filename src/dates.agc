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

# The length of `Sun, 06 Nov 1994 08:49:37 GMT`.
DATE_LENGTH = 29

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

## The Unix seconds of a date in the form `format` writes, the only form that a server must send (RFC 9110 section
## 5.6.7). The older forms and a date that is not that text are `none`, and a header with one is ignored.
export def parse(text: String) -> Optional[Int]
  value = text.strip
  parts = value.split(" ")
  if value.length != DATE_LENGTH or parts.size != 6 or parts[5] != "GMT" or not parts[0].end_with?(",")
    return none
  end

  clock = parts[4].split(":")
  if clock.size != 3
    return none
  end

  month = MONTH_NUMBERS.get(parts[2], 0)
  numbers = [parts[1], parts[3], clock[0], clock[1], clock[2]].map do |part| number(part) end
  if month == 0 or numbers.any? do |n| n < 0 end
    return none
  end

  day = numbers[0]
  year = numbers[1]
  hour = numbers[2]
  if day < 1 or day > 31 or hour > 23 or numbers[3] > 59 or numbers[4] > 60
    return none
  end

  days = days_since_epoch(year, month, day)
  return some(days * SECONDS_PER_DAY + hour * 3600 + numbers[3] * 60 + numbers[4])
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
