// PF-01 "Jam tenang" (proposed contract addition): local time from the device's IANA zone.

const FALLBACK_ZONE = "Asia/Jakarta";

/** True when the runtime knows the zone (Intl throws RangeError for unknown ones). */
export function isTimeZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

export interface LocalTime {
  /** Minutes after local midnight, 0–1439. */
  minutes: number;
  /** 0 = Sunday … 6 = Saturday. */
  weekday: number;
  /** Local calendar date, YYYY-MM-DD. */
  date: string;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** The wall clock in `zone` at `now`. An unknown zone (stored before a runtime update) falls back to WIB. */
export function localTime(zone: string, now: Date): LocalTime {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: isTimeZone(zone) ? zone : FALLBACK_ZONE,
    hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", weekday: "short",
  }).formatToParts(now);
  const get = (t: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === t)?.value ?? "";
  return {
    minutes: Number(get("hour")) * 60 + Number(get("minute")),
    weekday: WEEKDAYS.indexOf(get("weekday")),
    date: `${get("year")}-${get("month")}-${get("day")}`,
  };
}

export interface QuietHours {
  quietHours: boolean;
  quietStart: number;
  quietEnd: number;
  timeZone: string;
}

/** Inside the quiet window. A window may cross midnight (22:00–06:00); start == end means all day. */
export function isQuiet(q: QuietHours, now: Date): boolean {
  if (!q.quietHours) return false;
  const m = localTime(q.timeZone, now).minutes;
  if (q.quietStart === q.quietEnd) return true;
  return q.quietStart < q.quietEnd ? m >= q.quietStart && m < q.quietEnd : m >= q.quietStart || m < q.quietEnd;
}

/** "22:00" ↔ 1320. */
export const toClock = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
export const fromClock = (clock: string) => Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3, 5));
