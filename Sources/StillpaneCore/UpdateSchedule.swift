import Foundation

/// Decides when the update check may run.
///
/// The check is also the only evidence that an installed copy is still in
/// use, so its cadence defines that number: one request per calendar day the
/// app runs, and none beyond that. Checking at every launch would count a Mac
/// that relaunches three times as three copies.
public enum UpdateSchedule {
    /// True when nothing has been checked yet on `now`'s calendar day.
    ///
    /// A stamp in the future means the clock moved backwards, which would
    /// otherwise hold the check off until real time caught up.
    public static func isDue(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        if last > now { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}
