var DAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
var DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_ABBR = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var INVALID = { error: "Unrecognized time" }

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function formatDuration(seconds) {
  var minutes = Math.round(seconds / 60)
  var days = Math.floor(minutes / 1440)
  var hours = Math.floor(minutes % 1440 / 60)
  var text = (days ? days + "d" : "") + (hours ? hours + "h" : "") + (minutes % 60 ? minutes % 60 + "m" : "")
  return text || "0m"
}

// "30" (minutes), "90m", "1h30m", "2h" -> seconds, or 0
function durationSeconds(text) {
  var compact = text.replace(/ /g, "")
  var match = /^(\d+)$/.exec(compact)
  if (match) return Number(match[1]) * 60

  match = /^(?:(\d+)h)?(?:(\d+)m)?$/.exec(compact)
  if (!match || (!match[1] && !match[2])) return 0
  return (Number(match[1] || 0) * 60 + Number(match[2] || 0)) * 60
}

function clockTime(text) {
  var match = /^(\d{1,2}):(\d{2})$/.exec(text || "")
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return null
  return { hour: Number(match[1]), minute: Number(match[2]) }
}

function dayIndex(word) {
  if (word.length < 3) return -1
  for (var i = 0; i < DAY_NAMES.length; i++)
    if (DAY_NAMES[i].indexOf(word) === 0) return i
  return -1
}

// "day", "weekday", "mon,wed" -> sorted day indexes, or null
function daySet(text) {
  if (text === "day") return [0, 1, 2, 3, 4, 5, 6]
  if (text === "weekday" || text === "weekdays") return [1, 2, 3, 4, 5]

  var days = []
  var words = text.split(",")
  for (var i = 0; i < words.length; i++) {
    var day = dayIndex(words[i])
    if (day < 0) return null
    if (days.indexOf(day) < 0) days.push(day)
  }
  return days.sort()
}

// First hour:minute after now, within the next `limit` days, on a day accepted by dayOk
function nextMatch(now, time, dayOk, limit) {
  for (var i = 0; i <= limit; i++) {
    var date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i, time.hour, time.minute)
    if (date > now && dayOk(date)) return date
  }
  return null
}

function schedule(date, repeat, onCalendar, everySeconds) {
  return { at: Math.floor(date.getTime() / 1000), repeat: repeat || "", onCalendar: onCalendar || "", everySeconds: everySeconds || 0 }
}

function parseOnce(input, now) {
  var seconds = durationSeconds(input)
  if (seconds) return schedule(new Date(now.getTime() + seconds * 1000))

  var words = input.split(" ")
  var time = clockTime(words.pop())
  var head = words.join(" ")
  if (!time) return INVALID

  if (!head) return schedule(nextMatch(now, time, function() { return true }, 1))
  if (head === "tomorrow") return schedule(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, time.hour, time.minute))

  var day = dayIndex(head)
  if (day >= 0) return schedule(nextMatch(now, time, function(date) { return date.getDay() === day }, 7))

  var iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(head)
  if (!iso) return INVALID

  var date = new Date(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]), time.hour, time.minute)
  if (date.getMonth() !== Number(iso[2]) - 1 || date.getDate() !== Number(iso[3])) return { error: "Invalid date" }
  if (date <= now) return { error: "That time has passed" }
  return schedule(date)
}

function parseRepeat(input, now) {
  var seconds = durationSeconds(input)
  if (seconds) return schedule(new Date(now.getTime() + seconds * 1000), "every " + formatDuration(seconds), "", seconds)

  var words = input.split(" ")
  var time = words.length === 2 ? clockTime(words[1]) : null
  if (!time) return INVALID

  var clock = pad(time.hour) + ":" + pad(time.minute) + ":00"
  var ordinal = /^(\d{1,2})(st|nd|rd|th)$/.exec(words[0])
  if (ordinal) {
    var monthDay = Number(ordinal[1])
    if (monthDay < 1 || monthDay > 31) return INVALID
    // ponytail: 62 days always reaches the next month that has this day
    return schedule(nextMatch(now, time, function(date) { return date.getDate() === monthDay }, 62), "monthly", "*-*-" + pad(monthDay) + " " + clock)
  }

  var days = daySet(words[0])
  if (!days) return INVALID

  var date = nextMatch(now, time, function(date) { return days.indexOf(date.getDay()) >= 0 }, 7)
  if (days.length === 7) return schedule(date, "daily", "*-*-* " + clock)

  var names = days.map(function(day) { return DAY_ABBR[day] })
  return schedule(date, days.join() === "1,2,3,4,5" ? "weekdays" : names.join(", "), names.join(",") + " *-*-* " + clock)
}

// Returns { at, repeat, onCalendar, everySeconds } or { error }.
// at is the first fire time in epoch seconds; onCalendar / everySeconds are set for repeats.
function parse(text, now) {
  now = now || new Date()
  var input = String(text || "").trim().toLowerCase().replace(/\s*,\s*/g, ",").replace(/\s+/g, " ")
  if (!input) return { error: "Enter a time" }

  var every = /^every (.+)$/.exec(input)
  return every ? parseRepeat(every[1], now) : parseOnce(input, now)
}

// Moves the time in `text` by `minutes` and returns the new text, or null when
// it cannot move: interval repeats and unrecognized input. A trailing clock time
// is replaced in place (wrapping at midnight, prefix kept), a duration stays a
// duration (at least 1m), and empty text becomes the clock time `now` + minutes.
function shift(text, minutes, now) {
  now = now || new Date()
  var input = String(text || "").trim()
  if (!input) {
    var from = new Date(now.getTime() + minutes * 60000)
    return pad(from.getHours()) + ":" + pad(from.getMinutes())
  }

  var result = parse(input, now)
  if (result.everySeconds) return null

  var clock = /(\d{1,2}):(\d{2})$/.exec(input)
  // A date scrolled into the past still moves, so it can be scrolled back
  if (clock && (!result.error || result.error === "That time has passed")) {
    var total = ((Number(clock[1]) * 60 + Number(clock[2]) + minutes) % 1440 + 1440) % 1440
    return input.slice(0, clock.index) + pad(Math.floor(total / 60)) + ":" + pad(total % 60)
  }

  var seconds = result.error ? 0 : durationSeconds(input.toLowerCase())
  if (!seconds) return null
  var length = Math.max(1, Math.round(seconds / 60) + minutes)
  return (length >= 60 ? Math.floor(length / 60) + "h" : "") + (length % 60 ? length % 60 + "m" : "")
}

// "Thu 14:30 · in 2h10m · daily"; without the clock time when the caller shows it
function describe(result, now, withoutTime) {
  if (result.error) return result.error

  now = now || new Date()
  var date = new Date(result.at * 1000)
  var seconds = result.at - now.getTime() / 1000
  var day = DAY_ABBR[date.getDay()] + (seconds >= 6 * 86400 ? " " + date.getDate() + " " + MONTH_ABBR[date.getMonth()] : "")
  var parts = [day + (withoutTime ? "" : " " + pad(date.getHours()) + ":" + pad(date.getMinutes())), "in " + formatDuration(seconds)]
  if (result.repeat) parts.push(result.repeat)
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    describe: describe,
    shift: shift,
    formatDuration: formatDuration
  }
}
