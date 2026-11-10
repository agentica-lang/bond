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
  "#{WEEKDAYS[days % 7]}, #{two(day)} #{MONTHS[month - 1]} #{year} #{clock} GMT"
end

## The Unix seconds of a date in one of the three forms that a recipient reads (RFC 9110 section 5.6.7): the one
## `format` writes (`Sun, 06 Nov 1994 08:49:37 GMT`), the old `Sunday, 06-Nov-94 08:49:37 GMT` (a year of two digits
## that is more than 50 years ahead is read as the last past year with those digits) and `Sun Nov  6 08:49:37 1994`. Any other text is `none`, and a
## header with one is ignored. The name of the weekday is not checked.
export def parse(text: String) -> Optional[Int]
  parts = text.strip.replace("  ", " ").split(" ")
  if parts.size == 6 and parts[5] == "GMT" and parts[0].end_with?(",")
    return assemble(parts[1], parts[2], parts[3], parts[4])
  end

  if parts.size == 4 and parts[3] == "GMT" and parts[0].end_with?(",")
    pieces = parts[1].split("-")
    return assemble(pieces[0], pieces[1], pieces[2], parts[2]) if pieces.size == 3
  end

  return assemble(parts[2], parts[1], parts[4], parts[3]) if parts.size == 5 and not parts[0].end_with?(",")

  none
end

### The year of the digits `year` (0 to 99) of the old form, by RFC 9110 section 5.6.7: the one of this century, unless
## that is more than 50 years after `current_year`, and then the one of the century before.
export def full_year(year: Int, current_year: Int) -> Int
  candidate = (current_year / 100) * 100 + year
  return candidate - 100 if candidate > current_year + 50

  candidate
end

# The seconds of the date made of the text of its parts, or `none` when one is not what it must be.
def assemble(day_text: String, month_text: String, year_text: String, clock_text: String) -> Optional[Int]
  clock = clock_text.split(":")
  month = MONTH_NUMBERS.get(month_text, 0)
  return none if clock.size != 3 or month == 0

  numbers = [day_text, year_text, clock[0], clock[1], clock[2]].map do |part| number(part) end
  return none if numbers.any? do |n| n < 0 end

  day = numbers[0]
  year = numbers[1]
  hour = numbers[2]
  if year_text.length == 2
    year = full_year(year, this_year())
  end

  return none if year_text.length != 2 and year_text.length != 4

  return none if day < 1 or day > 31 or hour > 23 or numbers[3] > 59 or numbers[4] > 60

  days = days_since_epoch(year, month, day)
  some(days * SECONDS_PER_DAY + hour * 3600 + numbers[3] * 60 + numbers[4])
end

def this_year() -> Int = format(Time.now_ms() / 1000).split(" ")[3].to_i!

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
  era * DAYS_PER_ERA + day_of_era - EPOCH_SHIFT
end

# The digits of `text` as a number, or -1 when it is not only digits.
def number(text: String) -> Int
  return -1 if text.empty? or not text.split("").all? do |ch| ch.code >= 48 and ch.code <= 57 end

  text.to_i!
end

def two(n: Int) -> String
  return "0#{n}" if n < 10

  n.to_s
end
