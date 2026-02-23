import Foundation
import FoundationModels

@available(iOS 26.0, *)
class RouteNLPParser {

    enum ParsingError: LocalizedError {
        case modelUnavailable
        case parsingFailed(String)
        case invalidDistance(Double)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "On-device AI model is not available. Make sure Apple Intelligence is enabled."
            case .parsingFailed(let reason):
                return "Could not understand the route request: \(reason)"
            case .invalidDistance(let d):
                return String(format: "Distance %.1f miles is outside the supported range (0.5–50 miles).", d)
            }
        }
    }

    func parseRequest(_ userInput: String) async throws -> RouteRequest {
        // Check if the on-device model is available
        guard SystemLanguageModel.default.isAvailable else {
            throw ParsingError.modelUnavailable
        }

        let session = LanguageModelSession()

        let instructions = """
        You are a running route assistant. Parse the user's request into structured route parameters.
        - Extract the target distance in miles. If they say kilometers, convert to miles (1 km = 0.621371 mi).
        - Determine route type: "loop" (circular, returns to start), "outAndBack" (go out and return same way), or "pointToPoint" (one direction).
        - If they mention a direction (e.g. "toward the city", "along the waterfront", "north"), extract it as directionPreference.
        - If they mention terrain (e.g. "flat", "hilly", "trail"), extract it as terrainPreference.
        - Default to "loop" if no route type is specified.
        - Default distance to 3.0 miles if no distance is specified.
        """

        let prompt = instructions + "\n\nUser: " + userInput
        let response: LanguageModelSession.Response<RouteRequest>
        do {
            response = try await session.respond(
                to: prompt,
                generating: RouteRequest.self
            )
        } catch {
            throw ParsingError.parsingFailed("The on-device AI model could not process this request. Make sure Apple Intelligence is fully enabled and the model assets are downloaded. (\(error.localizedDescription))")
        }
        let result = response.content

        guard result.targetDistanceMiles >= 0.5 && result.targetDistanceMiles <= 50.0 else {
            throw ParsingError.invalidDistance(result.targetDistanceMiles)
        }

        return result
    }
}

