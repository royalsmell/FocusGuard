import SwiftUI

struct DurationWheelPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            Picker("小时", selection: $hours) {
                ForEach(0..<24, id: \.self) { value in
                    Text("\(value) 小时").tag(value)
                }
            }
            .pickerStyle(.wheel)

            Picker("分钟", selection: $minutes) {
                ForEach(0..<60, id: \.self) { value in
                    Text("\(value) 分钟").tag(value)
                }
            }
            .pickerStyle(.wheel)
        }
        .frame(height: 150)
        .clipped()
    }
}

enum FocusDurationText {
    static func full(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0, remainingMinutes > 0 {
            return String(localized: "\(hours) 小时 \(remainingMinutes) 分钟")
        }
        if hours > 0 {
            return String(localized: "\(hours) 小时")
        }
        return String(localized: "\(remainingMinutes) 分钟")
    }

    static func compact(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h\(remainingMinutes)m"
        }
        if hours > 0 { return "\(hours)h" }
        return "\(remainingMinutes)m"
    }

    static func countdown(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
