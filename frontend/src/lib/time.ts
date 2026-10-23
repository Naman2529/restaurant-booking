// Every restaurant is in IST and the API speaks IST wall-clock strings like
// "2026-10-30T19:00". They are treated as plain text here and never passed
// through Date time zones, so a browser in another zone can't shift them.

const IST = 'Asia/Kolkata'

/** Today's date in IST as "YYYY-MM-DD". */
export function todayIST(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: IST }).format(new Date())
}

/** Current IST time as minutes since midnight. */
export function nowMinutesIST(): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: IST,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date())
  const h = Number(parts.find((p) => p.type === 'hour')?.value ?? 0)
  const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0)
  return h * 60 + m
}

/** "YYYY-MM-DD" plus n days, calendar arithmetic only (UTC noon avoids DST edges). */
export function addDays(date: string, n: number): string {
  const d = new Date(`${date}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

function asUTC(date: string) {
  return new Date(`${date}T12:00:00Z`)
}

/** "Sat 25 Oct" */
export function shortDate(date: string): string {
  return asUTC(date).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' })
}

/** "Saturday, 25 October" */
export function longDate(date: string): string {
  return asUTC(date).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' })
}

/** "19:00" from "2026-10-30T19:00" */
export function timeOf(stamp: string): string {
  return stamp.slice(11, 16)
}

/** "2026-10-30" from "2026-10-30T19:00" */
export function dateOf(stamp: string): string {
  return stamp.slice(0, 10)
}

/** "7:00 pm" from "19:00" */
export function friendlyTime(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number)
  const suffix = h >= 12 ? 'pm' : 'am'
  const h12 = h % 12 === 0 ? 12 : h % 12
  return `${h12}:${String(m).padStart(2, '0')} ${suffix}`
}

/** "Good morning" / "Good afternoon" / "Good evening" by IST time. */
export function greeting(): string {
  const m = nowMinutesIST()
  if (m < 12 * 60) return 'Good morning'
  if (m < 17 * 60) return 'Good afternoon'
  return 'Good evening'
}
