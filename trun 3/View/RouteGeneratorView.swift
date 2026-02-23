import SwiftUI
import MapKit

@available(iOS 26.0, *)
struct RouteGeneratorView: View {
    @StateObject private var generationService = RouteGenerationService()

    @Binding var routes: [String: [Route]]
    @Binding var selectedRoute: Route?
    @Binding var isPresented: Bool

    var userLocation: CLLocationCoordinate2D?

    @State private var userInput: String = ""
    @State private var routeName: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var generatedResult: (
        coordinates: [CLLocationCoordinate2D],
        gpxString: String,
        distanceMiles: Double
    )? = nil
    @State private var showNamePrompt: Bool = false
    @State private var selectedActivityType: ActivityType = .running

    var body: some View {
        NavigationView {
            ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Activity")
                        .font(.headline)
                    Spacer()
                    Menu {
                        Button(action: { selectedActivityType = .running }) {
                            Label("Running", systemImage: "figure.run")
                        }
                        Button(action: { selectedActivityType = .walking }) {
                            Label("Walking", systemImage: "figure.walk")
                        }
                        Button(action: { selectedActivityType = .cycling }) {
                            Label("Cycling", systemImage: "bicycle")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: activityIcon)
                            Text(activityLabel)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(activityColor.opacity(0.15))
                        .foregroundColor(activityColor)
                        .cornerRadius(8)
                    }
                    .disabled(generationService.isGenerating)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe your route")
                        .font(.headline)

                    TextField(
                        selectedActivityType == .cycling
                            ? "e.g., \"10 mile bike ride along the river\""
                            : "e.g., \"7 mile \(selectedActivityType == .running ? "run" : "walk") toward the city\"",
                        text: $userInput,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(generationService.isGenerating)
                }
                .padding(.horizontal)

                Button(action: { generateRoute() }) {
                    HStack {
                        if generationService.isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text(generationService.isGenerating ? generationService.generationProgress : "Generate Route")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(userInput.isEmpty || generationService.isGenerating ? Color.gray : activityColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(userInput.isEmpty || generationService.isGenerating)
                .padding(.horizontal)

                if let coords = generationService.previewCoordinates, !coords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(format: "%.1f miles", generationService.generatedDistanceMiles))
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                        }

                        Map {
                            MapPolyline(coordinates: coords)
                                .stroke(activityColor, lineWidth: 3)
                        }
                        .frame(height: 200)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("Regenerate") {
                            generatedResult = nil
                            generateRoute()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)

                        Button("Save Route") {
                            routeName = ""
                            showNamePrompt = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

            }
            .padding(.top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("AI Route Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Name Your Route", isPresented: $showNamePrompt) {
                TextField("Route name", text: $routeName)
                Button("Save") { saveRoute() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give your generated route a name.")
            }
        }
    }

    private var activityColor: Color {
        switch selectedActivityType {
        case .running: return .purple
        case .walking: return .green
        case .cycling: return .blue
        }
    }

    private var activityIcon: String {
        switch selectedActivityType {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }

    private var activityLabel: String {
        switch selectedActivityType {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        }
    }

    private func generateRoute() {
        guard let location = userLocation else {
            errorMessage = "Unable to determine your location."
            showError = true
            return
        }

        Task {
            do {
                let result = try await generationService.generateRoute(
                    userInput: userInput,
                    userLocation: location,
                    activityType: selectedActivityType
                )
                await MainActor.run {
                    generatedResult = result
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func saveRoute() {
        guard let result = generatedResult else { return }

        let sanitized = GPXValidator.sanitizeRouteName(routeName)
        let name = sanitized.isEmpty ? "AI Route" : sanitized

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = name.replacingOccurrences(of: " ", with: "_") + ".gpx"
        let fileURL = documentsURL.appendingPathComponent(filename)

        do {
            try result.gpxString.write(to: fileURL, atomically: true, encoding: .utf8)

            let maxId = routes["Run Detroit"]?.map { $0.id }.max() ?? 0
            let newRoute = Route(
                id: maxId + 1,
                name: name,
                GPXFileURL: fileURL.path,
                color: selectedActivityType == .cycling ? [0.2, 0.5, 1.0] : selectedActivityType == .running ? [0.6, 0.2, 1.0] : [0.4, 0.7, 0.3]
            )

            if routes["Run Detroit"] != nil {
                routes["Run Detroit"]?.append(newRoute)
            } else {
                routes["Run Detroit"] = [newRoute]
            }

            selectedRoute = newRoute
            isPresented = false

        } catch {
            errorMessage = "Could not save route: \(error.localizedDescription)"
            showError = true
        }
    }
}
