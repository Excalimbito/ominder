// Run with: node test.js
var TimeParser = require("./TimeParser.js")

// Thu 2026-10-01 12:19:30 local time
var now = new Date(2026, 9, 1, 12, 19, 30)

function local(at) {
  var date = new Date(at * 1000)
  function pad(n) { return (n < 10 ? "0" : "") + n }
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " +
    pad(date.getHours()) + ":" + pad(date.getMinutes()) + ":" + pad(date.getSeconds())
}

// [input, first fire, repeat label, OnCalendar, interval seconds]; first fire null means an error
var cases = [
  ["30", "2026-10-01 12:49:30", "", "", 0],
  ["90m", "2026-10-01 13:49:30", "", "", 0],
  ["1h30m", "2026-10-01 13:49:30", "", "", 0],
  ["1h 30m", "2026-10-01 13:49:30", "", "", 0],
  ["2h", "2026-10-01 14:19:30", "", "", 0],
  ["14:30", "2026-10-01 14:30:00", "", "", 0],
  ["9:00", "2026-10-02 09:00:00", "", "", 0],
  ["12:19", "2026-10-02 12:19:00", "", "", 0],
  ["Tomorrow 9:00", "2026-10-02 09:00:00", "", "", 0],
  ["fri 14:00", "2026-10-02 14:00:00", "", "", 0],
  ["thu 14:00", "2026-10-01 14:00:00", "", "", 0],
  ["thursday 9:00", "2026-10-08 09:00:00", "", "", 0],
  ["2026-10-05 9:00", "2026-10-05 09:00:00", "", "", 0],
  ["every 30m", "2026-10-01 12:49:30", "every 30m", "", 1800],
  ["every 90m", "2026-10-01 13:49:30", "every 1h30m", "", 5400],
  ["every day 8:00", "2026-10-02 08:00:00", "daily", "*-*-* 08:00:00", 0],
  ["every day 13:05", "2026-10-01 13:05:00", "daily", "*-*-* 13:05:00", 0],
  ["every mon,wed 9:00", "2026-10-05 09:00:00", "Mon, Wed", "Mon,Wed *-*-* 09:00:00", 0],
  ["every wed, mon 9:00", "2026-10-05 09:00:00", "Mon, Wed", "Mon,Wed *-*-* 09:00:00", 0],
  ["every weekday 9:00", "2026-10-02 09:00:00", "weekdays", "Mon,Tue,Wed,Thu,Fri *-*-* 09:00:00", 0],
  ["every 1st 10:00", "2026-11-01 10:00:00", "monthly", "*-*-01 10:00:00", 0],
  ["every 31st 10:00", "2026-10-31 10:00:00", "monthly", "*-*-31 10:00:00", 0],
  ["", null],
  ["0", null],
  ["abc", null],
  ["25:00", null],
  ["9:60", null],
  ["2026-09-30 9:00", null],
  ["2026-02-30 9:00", null],
  ["every", null],
  ["every 32nd 10:00", null],
  ["every funday 9:00", null],
  ["every day", null],
  ["every *-*-* 9:00", null]
]

var failures = 0

cases.forEach(function(c) {
  var result = TimeParser.parse(c[0], now)
  var actual = result.error ? [c[0], null] : [c[0], local(result.at), result.repeat, result.onCalendar, result.everySeconds]
  var expected = c[1] === null ? [c[0], null] : c
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++
    console.log("FAIL", JSON.stringify(c[0]), "expected", JSON.stringify(expected.slice(1)), "got", JSON.stringify(result.error || actual.slice(1)))
  }
})

var described = TimeParser.describe(TimeParser.parse("every day 14:30", now), now)
if (described !== "Thu 14:30 · in 2h11m · daily") {
  failures++
  console.log("FAIL describe:", described)
}

described = TimeParser.describe(TimeParser.parse("2026-10-20 9:00", now), now)
if (described !== "Tue 20 Oct 09:00 · in 18d20h41m") {
  failures++
  console.log("FAIL describe far:", described)
}

described = TimeParser.describe(TimeParser.parse("every day 14:30", now), now, true)
if (described !== "Thu · in 2h11m · daily") {
  failures++
  console.log("FAIL describe without time:", described)
}

// [text, minutes, expected]; null means the time cannot be scrolled
var shifts = [
  ["", 1, "12:20"],
  ["", -1, "12:18"],
  ["14:30", 1, "14:31"],
  ["9:59", 1, "10:00"],
  ["23:30", 60, "00:30"],
  ["0:00", -1, "23:59"],
  ["Tomorrow 9:00", -60, "Tomorrow 08:00"],
  ["fri 14:00", 5, "fri 14:05"],
  ["every mon,wed 9:00", 1, "every mon,wed 09:01"],
  ["every 1st 10:00", -1, "every 1st 09:59"],
  ["2026-10-01 12:20", -60, "2026-10-01 11:20"],
  ["2026-10-01 11:20", 60, "2026-10-01 12:20"],
  ["30", 1, "31m"],
  ["1h30m", -31, "59m"],
  ["1H 30m", 30, "2h"],
  ["2m", -5, "1m"],
  ["every 30m", 1, null],
  ["abc", 1, null],
  ["abc 9:00", 1, null]
]

shifts.forEach(function(c) {
  var actual = TimeParser.shift(c[0], c[1], now)
  if (actual !== c[2]) {
    failures++
    console.log("FAIL shift", JSON.stringify(c[0]), c[1], "expected", JSON.stringify(c[2]), "got", JSON.stringify(actual))
  }
})

console.log(failures ? failures + " failed" : cases.length + shifts.length + 3 + " passed")
process.exit(failures ? 1 : 0)
