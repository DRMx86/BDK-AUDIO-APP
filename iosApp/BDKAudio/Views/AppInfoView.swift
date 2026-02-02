import SwiftUI

// MARK: - App Info View (matching Android app info exactly)

struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(hex: "1a1a2e")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // App name and version
                        VStack(spacing: 16) {
                            Text("BDK Audio")
                                .font(.title.bold())
                                .foregroundColor(.white)
                            
                            Text("Version \(appVersion)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 40)
                        
                        // Description
                        Text("Control your BDK Bluetooth speaker with customizable EQ presets, LED effects, and more.")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        // Info cards
                        VStack(spacing: 16) {
                            InfoCardView(
                                icon: "person.fill",
                                title: "Developer",
                                value: "WillyBilly"
                            )
                            
                            InfoCardView(
                                icon: "envelope.fill",
                                title: "Contact",
                                value: "ngocviet050906@gmail.com"
                            )
                            
                            InfoCardView(
                                icon: "globe",
                                title: "Website",
                                value: "github.com/WillyBilly06"
                            )
                        }
                        .padding(.horizontal)
                        
                        // Copyright
                        Text("© 2024 WillyBilly. All rights reserved.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
}

// MARK: - Info Card View

struct InfoCardView: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.body)
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Link Button

struct LinkButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.cyan)
                
                Text(title)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

// MARK: - Previews

struct AppInfoView_Previews: PreviewProvider {
    static var previews: some View {
        AppInfoView()
    }
}
