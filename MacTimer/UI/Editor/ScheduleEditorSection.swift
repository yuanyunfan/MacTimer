import SwiftUI

struct ScheduleEditorSection: View {
    @Binding var schedule: ScheduleConfig

    private let weekdays = [(1, "周一"), (2, "周二"), (3, "周三"),
                            (4, "周四"), (5, "周五"), (6, "周六"), (7, "周日")]

    var body: some View {
        Section("执行方式") {
            Picker("", selection: $schedule.type) {
                ForEach(ScheduleType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if schedule.type == .fixedTime {
                fixedTimeFields
            } else {
                intervalFields
            }
        }
    }

    private var fixedTimeFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("重复周期").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(weekdays, id: \.0) { day, label in
                    let selected = schedule.fixedTime?.weekdays.contains(day) ?? false
                    Button(label) {
                        toggleWeekday(day)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : .secondary)
                    .font(.caption)
                }
            }
            HStack {
                Text("时刻").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    String(format: "%02d:%02d",
                           schedule.fixedTime?.hour ?? 9,
                           schedule.fixedTime?.minute ?? 0),
                    onIncrement: { incrementMinute(1) },
                    onDecrement: { incrementMinute(-1) }
                )
            }
        }
    }

    private var intervalFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("间隔（秒）").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("", value: Binding(
                    get: { schedule.interval?.seconds ?? 3600 },
                    set: { val in
                        let clamped = max(60, val)
                        schedule.interval = IntervalConfig(
                            seconds: clamped,
                            startImmediately: schedule.interval?.startImmediately ?? false
                        )
                    }
                ), format: .number)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            }
            Text("最小值 60 秒").font(.caption2).foregroundStyle(.tertiary)
            Toggle("启动时立即执行", isOn: Binding(
                get: { schedule.interval?.startImmediately ?? false },
                set: { val in
                    schedule.interval = IntervalConfig(
                        seconds: schedule.interval?.seconds ?? 3600,
                        startImmediately: val
                    )
                }
            ))
        }
    }

    private func toggleWeekday(_ day: Int) {
        var weekdays = schedule.fixedTime?.weekdays ?? []
        if weekdays.contains(day) {
            weekdays.removeAll { $0 == day }
        } else {
            weekdays.append(day)
            weekdays.sort()
        }
        let hour = schedule.fixedTime?.hour ?? 9
        let minute = schedule.fixedTime?.minute ?? 0
        schedule.fixedTime = FixedTimeConfig(weekdays: weekdays, hour: hour, minute: minute)
    }

    private func incrementMinute(_ delta: Int) {
        var hour = schedule.fixedTime?.hour ?? 9
        var minute = (schedule.fixedTime?.minute ?? 0) + delta
        if minute < 0 { minute = 59; hour = max(0, hour - 1) }
        if minute >= 60 { minute = 0; hour = min(23, hour + 1) }
        schedule.fixedTime = FixedTimeConfig(
            weekdays: schedule.fixedTime?.weekdays ?? [1],
            hour: hour,
            minute: minute
        )
    }
}
