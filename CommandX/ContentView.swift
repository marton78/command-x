// ContentView.swift
// Command X
//
// Main UI for settings and status.

import SwiftUI
import ApplicationServices

struct ContentView: View {
    @AppStorage("cutSoundEnabled") var cutSoundEnabled: Bool = true
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var showPermissionAlert = false
    @State private var launchAtLogin: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Command + X")
                .font(.title2)
                .bold()
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Grouped box
            VStack(alignment: .leading, spacing: 16) {
                // Allow access
                HStack(alignment: .top) {
                    Toggle(isOn: .constant(isAccessibilityGranted)) {
                        Text("Allow Command + X to access")
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    .disabled(true)

                    if !isAccessibilityGranted {
                        Button("Open Accessibility Settings…") {
                            openSystemSettings()
                        }
                        .buttonStyle(.link)
                    }
                }
                if isAccessibilityGranted {
                    Text("Accessibility permission is granted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                } else {
                    Text("System Preferences → Security & Privacy → Accessibility → Add Command + X and check")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 28)
                }

                // Sound effect
                Toggle(isOn: $cutSoundEnabled) {
                    Text("Enable the cutting sound effect")
                }
                .toggleStyle(CheckboxToggleStyle())

                // Launch at login
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                }
                .toggleStyle(CheckboxToggleStyle())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
            .padding([.leading, .trailing, .bottom], 16)

            // Quit button
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text("Quit Command X")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(width: 380)
        .onAppear {
            isAccessibilityGranted = AXIsProcessTrusted()
            // Delay sync to avoid issues during view initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = AXIsProcessTrusted()
        }
        .onChange(of: launchAtLogin) { newValue in
            LaunchAtLoginManager.shared.isEnabled = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandXPermissionError"))) { _ in
            showPermissionAlert = true
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text("Command X needs Accessibility and Automation permissions to control Finder and System Events. Please grant these in System Settings > Privacy & Security > Accessibility (add Command X) and Automation (allow control of Finder and System Events)."),
                primaryButton: .default(Text("Open System Settings"), action: {
                    openSystemSettings()
                }),
                secondaryButton: .cancel()
            )
        }
    }

    private func openSystemSettings() {
        // Open System Settings > Privacy & Security > Accessibility
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
