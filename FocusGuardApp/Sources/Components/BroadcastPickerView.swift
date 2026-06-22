import ReplayKit
import SharedCore
import SwiftUI
import UIKit

struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String?
    let tintColor: UIColor

    init(
        preferredExtension: String? = SharedConstants.broadcastExtensionBundleIdentifier,
        tintColor: UIColor = .systemIndigo
    ) {
        self.preferredExtension = preferredExtension
        self.tintColor = tintColor
    }

    func makeUIView(context: Context) -> FullSizeSystemBroadcastPickerView {
        let picker = FullSizeSystemBroadcastPickerView(frame: .zero)
        configure(picker)
        return picker
    }

    func updateUIView(_ uiView: FullSizeSystemBroadcastPickerView, context: Context) {
        configure(uiView)
    }

    private func configure(_ picker: RPSystemBroadcastPickerView) {
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = false
        picker.tintColor = tintColor
        picker.isUserInteractionEnabled = true
    }
}

final class FullSizeSystemBroadcastPickerView: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}

struct BroadcastPickerButton: View {
    let preferredExtension: String?

    var body: some View {
        ZStack {
            BroadcastPickerView(preferredExtension: preferredExtension, tintColor: .clear)
            Label("授权屏幕共享", systemImage: "rectangle.on.rectangle")
                .font(.headline)
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(.indigo, in: .rect(cornerRadius: 16))
        .accessibilityLabel("授权屏幕共享")
        .accessibilityHint("打开系统屏幕广播选择器")
    }
}
