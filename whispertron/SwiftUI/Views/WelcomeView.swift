import SwiftUI
import KeyboardShortcuts

struct WelcomeView: View {
  var onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)

      Text("Whispertron")
        .font(.title)
        .fontWeight(.bold)

      VStack(alignment: .leading, spacing: 12) {
        Label("Press **F13** to start dictating", systemImage: "keyboard")
        Label("Hold the key, speak, release — text appears at cursor", systemImage: "text.cursor")
      }
      .font(.body)

      Divider()

      HStack {
        Circle()
          .fill(isAccessibilityEnabled ? Color.green : Color.red)
          .frame(width: 8, height: 8)
        Text(isAccessibilityEnabled ? "Accessibility: Enabled" : "Accessibility: Not Enabled")
          .font(.caption)

        if !isAccessibilityEnabled {
          Button("Open System Settings") {
            NSWorkspace.shared.open(
              URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
          }
          .font(.caption)
        }
      }

      Button("Get Started") {
        onDismiss()
      }
      .keyboardShortcut(.defaultAction)
    }
    .padding(30)
    .frame(width: 400, height: 320)
  }

  private var isAccessibilityEnabled: Bool {
    AXIsProcessTrusted()
  }
}
