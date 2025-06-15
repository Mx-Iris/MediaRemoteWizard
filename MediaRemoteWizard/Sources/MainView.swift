import SwiftUI
import LaunchAtLogin

struct MainView: View {
    @EnvironmentObject
    private var client: MediaRemoteWizardClient

    @State
    private var error: String?

    @State
    private var isPresentedError: Bool = false

    @AppStorage("showMainWindowOnLaunch")
    private var showMainWindowOnLaunch: Bool = true
    
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 100, height: 100)

        Form {
            Section {
                HStack {
                    Text("Install Helper")

                    Spacer()

                    Button {
                        Task {
                            do {
                                try await client.installHelper()
                            } catch {
                                print(error)
                                self.error = "\(error)"
                                self.isPresentedError = true
                            }
                        }
                    } label: {
                        if client.isHelperConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack {
                    LaunchAtLogin.Toggle {
                        Text("Launch at login")
                    }
                }
                
                HStack {
                    Toggle(isOn: $showMainWindowOnLaunch) {
                        Text("Show main window")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: $isPresentedError, presenting: error) { _ in
            Text("OK")
        } message: { error in
            Text("\(error)")
        }
        .frame(maxWidth: 300)
    }
}

@available(macOS 14.0, *)
#Preview {
    MainView()
        .environmentObject(MediaRemoteWizardClient())
}
