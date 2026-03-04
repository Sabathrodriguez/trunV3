import SwiftUI
import MapKit
import UniformTypeIdentifiers

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
    @State private var selectedOption: RouteOption? = nil
    @State private var showNamePrompt: Bool = false
    @State private var selectedActivityType: ActivityType = .running
    @State private var showFileExporter: Bool = false
    @State private var gpxDocumentToExport: GPXDocument?
    @State private var exportFileName: String = "route"

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

                if !generationService.routeOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose a route")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(generationService.routeOptions) { option in
                            routeOptionCard(option)
                                .padding(.horizontal)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Regenerate") {
                            selectedOption = nil
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
                        .background(selectedOption != nil ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(selectedOption == nil)
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
            .fileExporter(
                isPresented: $showFileExporter,
                document: gpxDocumentToExport,
                contentType: UTType(filenameExtension: "gpx") ?? .xml,
                defaultFilename: exportFileName
            ) { result in
                switch result {
                case .success:
                    isPresented = false
                case .failure(let error):
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    // MARK: - Route Option Card

    @ViewBuilder
    private func routeOptionCard(_ option: RouteOption) -> some View {
        let isSelected = selectedOption?.id == option.id

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: option.source == "Apple Maps" ? "map.fill" : "globe")
                    .foregroundColor(option.source == "Apple Maps" ? .blue : .orange)
                Text(option.source)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.1f mi", option.distanceMiles))
                    .font(.subheadline)
                    .fontWeight(.bold)
            }

            Map {
                ForEach(RouteAnnotationHelpers.rainbowSegments(from: option.coordinates)) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, lineWidth: 4)
                }

                ForEach(RouteAnnotationHelpers.generateArrows(from: option.coordinates)) { arrow in
                    Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                        Image(systemName: "arrowtriangle.forward.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 1)
                            .rotationEffect(.degrees(arrow.bearing - 90))
                    }
                }
            }
            .frame(height: 180)
            .cornerRadius(10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? activityColor : Color.clear, lineWidth: 3)
        )
        .onTapGesture {
            selectedOption = option
        }
    }

    // MARK: - Helpers

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
                try await generationService.generateRoute(
                    userInput: userInput,
                    userLocation: location,
                    activityType: selectedActivityType
                )
                await MainActor.run {
                    // Auto-select the first option
                    if let first = generationService.routeOptions.first {
                        selectedOption = first
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    print("Route generation error: \(errorMessage)")
                }
            }
        }
    }

    private func saveRoute() {
        guard let option = selectedOption else { return }

        let sanitized = GPXValidator.sanitizeRouteName(routeName)
        let name = sanitized.isEmpty ? "AI Route" : sanitized
        let filename = name.replacingOccurrences(of: " ", with: "_") + ".gpx"

        gpxDocumentToExport = GPXDocument(text: option.gpxString)
        exportFileName = filename
        showFileExporter = true
    }
}
