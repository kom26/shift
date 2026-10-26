import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(AlarmKit)
struct ShiftAlarmMetadata: AlarmMetadata {}
#endif

/// iPhone の本物のアラーム(iOS 26 の AlarmKit)をセット・解除する
@MainActor
final class AlarmService {
    static let shared = AlarmService()

    enum Outcome: Equatable {
        case set, removed
        case noShift, past, denied, unsupported, failed
    }

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// stamp のアラームを日付 ds にセットする。すでにあれば解除する
    func toggle(spec: AlarmPreset, on ds: String, store: Store) async -> Outcome {
        guard Self.isSupported else { return .unsupported }
        if let existing = store.alarmEntry(matching: spec, on: ds) {
            await cancel(id: existing.id)
            store.removeAlarmEntry(id: existing.id)
            return .removed
        }
        guard let fire = AlarmMath.fireDate(preset: spec, on: ds, events: store.events) else { return .noShift }
        guard fire > Date() else { return .past }
        guard await authorize() else { return .denied }
        let id = UUID().uuidString
        guard await schedule(id: id, at: fire, spec: spec) else { return .failed }
        store.addAlarmEntry(AlarmEntry(id: id, kind: spec.kind, minutes: spec.minutes, date: ds,
                                       fireTime: fire.timeIntervalSince1970))
        return .set
    }

    /// 起動時・復帰時の同期。過ぎた記録を消し、シフト前のアラームは予定の変更に合わせて入れ直す
    func refresh(store: Store) async {
        guard Self.isSupported else { return }
        store.pruneAlarmEntries()
        for e in store.alarmEntries where e.kind == .beforeShift {
            let spec = AlarmPreset(kind: e.kind, minutes: e.minutes)
            guard let fire = AlarmMath.fireDate(preset: spec, on: e.date, events: store.events), fire > Date() else {
                await cancel(id: e.id)
                store.removeAlarmEntry(id: e.id)
                continue
            }
            if abs(fire.timeIntervalSince1970 - e.fireTime) >= 1 {
                await cancel(id: e.id)
                if await schedule(id: e.id, at: fire, spec: spec) {
                    store.updateAlarmFireTime(id: e.id, to: fire.timeIntervalSince1970)
                } else {
                    store.removeAlarmEntry(id: e.id)
                }
            }
        }
    }

    // MARK: AlarmKit

    private func authorize() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            switch manager.authorizationState {
            case .authorized: return true
            case .denied: return false
            default:
                return (try? await manager.requestAuthorization()) == .authorized
            }
        }
        #endif
        return false
    }

    private func schedule(id: String, at date: Date, spec: AlarmPreset) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let uuid = UUID(uuidString: id) {
            let title = LocalizedStringResource(stringLiteral: "シフト(\(spec.label))")
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: title)
            } else {
                let stop = AlarmButton(text: LocalizedStringResource(stringLiteral: "停止"),
                                       textColor: Color.white, systemImageName: "stop.circle")
                alert = AlarmPresentation.Alert(title: title, stopButton: stop)
            }
            let attributes = AlarmAttributes<ShiftAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: ShiftAlarmMetadata(),
                tintColor: Color.orange)
            let config = AlarmManager.AlarmConfiguration<ShiftAlarmMetadata>.alarm(
                schedule: .fixed(date), attributes: attributes)
            do {
                _ = try await AlarmManager.shared.schedule(id: uuid, configuration: config)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    private func cancel(id: String) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let uuid = UUID(uuidString: id) {
            try? AlarmManager.shared.cancel(id: uuid)
        }
        #endif
    }
}
