import SharedCore
import SwiftUI

struct DurationPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let index: Int
    @State private var hours: Int
    @State private var minutes: Int

    init(index: Int, initialMinutes: Int) {
        self.index = index
        let components = FocusDuration.components(totalMinutes: initialMinutes)
        _hours = State(initialValue: components.hours)
        _minutes = State(initialValue: components.minutes)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("快捷时长 \(index + 1)")
                .font(.title2.bold())
            Text(FocusDurationText.full(minutes: totalMinutes))
                .font(.title3.monospacedDigit())
                .foregroundStyle(totalMinutes > 0 ? Color.primary : Color.red)
            DurationWheelPicker(hours: $hours, minutes: $minutes)
            Spacer()
        }
        .padding()
        .navigationTitle("编辑快捷时长")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    model.saveQuickDuration(at: index, minutes: totalMinutes)
                    if model.errorMessage == nil { dismiss() }
                }
                .disabled(totalMinutes < DurationPreferences.allowedMinutes.lowerBound)
            }
        }
    }

    private var totalMinutes: Int {
        FocusDuration.totalMinutes(hours: hours, minutes: minutes)
    }
}
