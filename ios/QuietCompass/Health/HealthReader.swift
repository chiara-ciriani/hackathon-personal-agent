import HealthKit
import QuietCore

@MainActor
final class HealthReader {
    private let store = HKHealthStore()
    private let sleep = HKCategoryType(.sleepAnalysis)
    private let steps = HKQuantityType(.stepCount)
    private let heart = HKQuantityType(.restingHeartRate)
    private let hrv = HKQuantityType(.heartRateVariabilitySDNN)

    func preview() async throws -> HealthSummary {
        guard HKHealthStore.isHealthDataAvailable() else { throw PhoneError.message("Apple Health is unavailable on this device.") }
        try await store.requestAuthorization(toShare: [], read: [sleep, steps, heart, hrv])
        let now = Date(), calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -1, to: end) else { throw PhoneError.message("Could not determine the reporting day.") }
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        var metrics: [HealthMetric] = []
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: sleep, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKCategorySample] ?? []) }
            })
        }
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let intervals = samples.filter { asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        if !intervals.isEmpty {
            metrics.append(.init(name: "sleep_seconds", value: SleepIntervals.seconds(intervals, within: .init(start: start, end: end)), unit: "seconds", day: day))
        }
        // HealthKit statistics handles cumulative sources; do not sum raw phone + watch step samples.
        let quantities: [(HKQuantityType, HKStatisticsOptions, HKUnit, String, String)] = [
            (steps, .cumulativeSum, .count(), "steps", "count"),
            (heart, .discreteAverage, HKUnit.count().unitDivided(by: .minute()), "resting_heart_rate_bpm", "bpm"),
            (hrv, .discreteAverage, .secondUnit(with: .milli), "hrv_sdnn_ms", "ms")
        ]
        for (type, options, unit, name, unitName) in quantities {
            if let value = try await statistic(type, options: options, unit: unit, predicate: predicate) {
                metrics.append(.init(name: name, value: value, unit: unitName, day: day))
            }
        }
        return HealthSummary(capturedAt: now, metrics: metrics,
            note: "Previous local calendar day (\(calendar.timeZone.identifier)); missing data may mean no samples or access was not granted. Daily summaries, not live measurements.")
    }

    private func statistic(_ type: HKQuantityType, options: HKStatisticsOptions, unit: HKUnit,
                           predicate: NSPredicate) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, result, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else { continuation.resume(throwing: error) }
                    return
                }
                let quantity = options == .cumulativeSum ? result?.sumQuantity() : result?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            })
        }
    }
}
