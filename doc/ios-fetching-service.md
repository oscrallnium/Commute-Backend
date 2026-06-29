# CommuteBeh iOS — Networking Service Guide

This document covers how to implement the API client layer for the CommuteBeh iOS app. It maps directly to the endpoints in `doc/api.md`.

---

## Configuration

```swift
enum APIConfig {
    static let baseURL = "https://commute-backend-a6lj.onrender.com"
    // static let baseURL = "http://localhost:3000"  // local dev
}
```

---

## Token storage (Keychain)

Tokens must be stored in the Keychain — never `UserDefaults`.

```swift
import Security

enum Keychain {
    private static let service = "com.commutebeh.app"

    static func save(token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "jwt",
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "jwt",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "jwt"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

---

## API client

```swift
import Foundation

enum APIError: Error {
    case unauthorized           // 401 — token expired or revoked
    case forbidden              // 403 — wrong role
    case notFound               // 404
    case unprocessable(String)  // 422 — validation error from server
    case tooManyRequests        // 429
    case serverError(Int)       // 5xx
    case decodingFailed(Error)
    case network(Error)
}

final class APIClient {
    static let shared = APIClient()
    private let session = URLSession.shared
    private var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {}

    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        responseType: T.Type
    ) async throws -> T {
        var urlRequest = try endpoint.urlRequest()
        if let token = Keychain.load() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 422:
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "Validation failed"
            throw APIError.unprocessable(msg)
        case 429:
            throw APIError.tooManyRequests
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    // Fire-and-forget variant used for analytics (never blocks the caller)
    func send(_ endpoint: APIEndpoint) {
        Task {
            var urlRequest = (try? endpoint.urlRequest()) ?? URLRequest(url: URL(string: APIConfig.baseURL)!)
            if let token = Keychain.load() {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await session.data(for: urlRequest)
        }
    }
}

struct ErrorResponse: Decodable {
    let error: String
    let errors: [String]?
}
```

---

## Endpoint enum

```swift
enum APIEndpoint {
    // Auth
    case register(email: String, password: String, confirmation: String, displayName: String)
    case signIn(email: String, password: String)
    case signOut
    case refreshToken
    case deleteAccount

    // User
    case me
    case updateMe(displayName: String?, homeStationId: String?)

    // Graph
    case graphVersion
    case graph

    // Stations
    case stations(query: String?)
    case station(id: String)

    // Routes
    case routes
    case route(lineId: String)

    // Saved routes
    case savedRoutes
    case createSavedRoute(name: String, origin: String, destination: String, lineIds: [String])
    case deleteSavedRoute(id: String)

    // Incidents
    case incidents
    case reportIncident(stationId: String, description: String, category: String)

    // Analytics
    case logRoutePlan(origin: String, destination: String, lineIds: [String], durationSecs: Int)

    func urlRequest() throws -> URLRequest {
        let base = URL(string: APIConfig.baseURL)!
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!

        if let q = queryItems { components.queryItems = q }

        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if let body = body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return req
    }

    private var path: String {
        switch self {
        case .register:                    return "/auth/register"
        case .signIn:                      return "/auth/sign_in"
        case .signOut:                     return "/auth/sign_out"
        case .refreshToken:                return "/api/v1/auth/refresh"
        case .deleteAccount:               return "/api/v1/auth/account"
        case .me:                          return "/api/v1/me"
        case .updateMe:                    return "/api/v1/me"
        case .graphVersion:                return "/api/v1/graph/version"
        case .graph:                       return "/api/v1/graph"
        case .stations:                    return "/api/v1/stations"
        case .station(let id):             return "/api/v1/stations/\(id)"
        case .routes:                      return "/api/v1/routes"
        case .route(let lineId):           return "/api/v1/routes/\(lineId)"
        case .savedRoutes:                 return "/api/v1/saved_routes"
        case .createSavedRoute:            return "/api/v1/saved_routes"
        case .deleteSavedRoute(let id):    return "/api/v1/saved_routes/\(id)"
        case .incidents:                   return "/api/v1/incidents"
        case .reportIncident:              return "/api/v1/incidents"
        case .logRoutePlan:                return "/api/v1/analytics/route_plan"
        }
    }

    private var method: String {
        switch self {
        case .register, .signIn, .refreshToken, .createSavedRoute, .reportIncident, .logRoutePlan:
            return "POST"
        case .updateMe:
            return "PATCH"
        case .signOut, .deleteAccount, .deleteSavedRoute:
            return "DELETE"
        default:
            return "GET"
        }
    }

    private var queryItems: [URLQueryItem]? {
        switch self {
        case .stations(let q) where q != nil:
            return [URLQueryItem(name: "q", value: q)]
        default:
            return nil
        }
    }

    private var body: [String: Any]? {
        switch self {
        case .register(let email, let password, let confirmation, let displayName):
            return ["user": ["email": email, "password": password,
                             "password_confirmation": confirmation, "display_name": displayName]]
        case .signIn(let email, let password):
            return ["user": ["email": email, "password": password]]
        case .updateMe(let displayName, let homeStationId):
            var user: [String: Any] = [:]
            if let d = displayName { user["display_name"] = d }
            if let h = homeStationId { user["home_station_id"] = h }
            return ["user": user]
        case .createSavedRoute(let name, let origin, let destination, let lineIds):
            return ["saved_route": ["name": name, "origin_station_id": origin,
                                    "destination_station_id": destination, "line_ids": lineIds]]
        case .reportIncident(let stationId, let description, let category):
            return ["incident": ["station_id": stationId, "description": description,
                                 "category": category]]
        case .logRoutePlan(let origin, let destination, let lineIds, let durationSecs):
            return ["event": ["origin_station_id": origin, "destination_station_id": destination,
                              "line_ids": lineIds, "duration_seconds": durationSecs]]
        default:
            return nil
        }
    }
}
```

---

## Response models

```swift
// Wrapper used by all authenticated endpoints
struct APIResponse<T: Decodable>: Decodable {
    let data: T
}

// Auth
struct AuthPayload: Decodable {
    let token: String
    let user: UserProfile
}

struct UserProfile: Decodable {
    let id: String
    let email: String
    let displayName: String
    let role: String
    let homeStationId: String?
}

// Station
struct Station: Decodable {
    let stationId: String
    let name: String
    let latitude: Double
    let longitude: Double
    let lineIds: [String]
    let isTerminal: Bool
}

// Route
struct Route: Decodable {
    let lineId: String
    let name: String
    let color: String?
}

// Saved route
struct SavedRoute: Decodable {
    let id: String
    let name: String
    let originStationId: String
    let destinationStationId: String
    let lineIds: [String]
    let createdAt: String
}

// Incident
struct Incident: Decodable {
    let id: String
    let stationId: String
    let description: String
    let category: String
    let reportedAt: String
}

// Graph version
struct GraphVersion: Decodable {
    let version: String
    let updatedAt: String
}
```

---

## Auth service

Handles login, registration, token rotation, and logout. Hold the token in Keychain; refresh before it expires.

```swift
final class AuthService {
    static let shared = AuthService()
    private let client = APIClient.shared

    func register(email: String, password: String, displayName: String) async throws -> UserProfile {
        let resp: APIResponse<AuthPayload> = try await client.request(
            .register(email: email, password: password,
                      confirmation: password, displayName: displayName),
            responseType: APIResponse<AuthPayload>.self
        )
        Keychain.save(token: resp.data.token)
        return resp.data.user
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let resp: APIResponse<AuthPayload> = try await client.request(
            .signIn(email: email, password: password),
            responseType: APIResponse<AuthPayload>.self
        )
        Keychain.save(token: resp.data.token)
        return resp.data.user
    }

    // Call this on app launch if a token is already stored, before it expires
    func refresh() async throws -> UserProfile {
        let resp: APIResponse<AuthPayload> = try await client.request(
            .refreshToken,
            responseType: APIResponse<AuthPayload>.self
        )
        Keychain.save(token: resp.data.token)  // old token is immediately revoked server-side
        return resp.data.user
    }

    func signOut() async {
        _ = try? await client.request(.signOut, responseType: EmptyResponse.self)
        Keychain.delete()
    }

    func deleteAccount() async throws {
        _ = try? await client.request(.deleteAccount, responseType: EmptyResponse.self)
        Keychain.delete()
    }
}

struct EmptyResponse: Decodable {}
```

---

## Handling 401 globally

When any request returns `APIError.unauthorized`, redirect to the login screen. The JTI has been revoked server-side — refreshing will not help.

```swift
// In your view model or coordinator:
do {
    let routes = try await RouteService.shared.savedRoutes()
    // ...
} catch APIError.unauthorized {
    Keychain.delete()
    // Post notification or call coordinator to present login
    NotificationCenter.default.post(name: .sessionExpired, object: nil)
} catch {
    // Handle other errors
}

extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}
```

---

## Route service

```swift
final class RouteService {
    static let shared = RouteService()
    private let client = APIClient.shared

    func stations(query: String? = nil) async throws -> [Station] {
        let resp: APIResponse<[Station]> = try await client.request(
            .stations(query: query),
            responseType: APIResponse<[Station]>.self
        )
        return resp.data
    }

    func routes() async throws -> [Route] {
        let resp: APIResponse<[Route]> = try await client.request(
            .routes,
            responseType: APIResponse<[Route]>.self
        )
        return resp.data
    }

    func savedRoutes() async throws -> [SavedRoute] {
        let resp: APIResponse<[SavedRoute]> = try await client.request(
            .savedRoutes,
            responseType: APIResponse<[SavedRoute]>.self
        )
        return resp.data
    }

    func saveRoute(name: String, origin: String, destination: String, lineIds: [String]) async throws -> SavedRoute {
        let resp: APIResponse<SavedRoute> = try await client.request(
            .createSavedRoute(name: name, origin: origin, destination: destination, lineIds: lineIds),
            responseType: APIResponse<SavedRoute>.self
        )
        return resp.data
    }

    func deleteSavedRoute(id: String) async throws {
        _ = try await client.request(.deleteSavedRoute(id: id), responseType: EmptyResponse.self)
    }
}
```

---

## Graph service

The transit graph is cached locally. Check `graphVersion` on app launch; if the version differs from what's stored, re-fetch and cache.

```swift
final class GraphService {
    static let shared = GraphService()
    private let client = APIClient.shared

    func currentVersion() async throws -> GraphVersion {
        let resp: APIResponse<GraphVersion> = try await client.request(
            .graphVersion,
            responseType: APIResponse<GraphVersion>.self
        )
        return resp.data
    }

    // Returns raw JSON data — parse with your transit graph model
    func fetchGraph() async throws -> Data {
        let req = try APIEndpoint.graph.urlRequest()
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
```

---

## Analytics service

Analytics calls never throw — they run in the background so a logging failure never blocks the commuter.

```swift
final class AnalyticsService {
    static let shared = AnalyticsService()
    private let client = APIClient.shared

    func logRoutePlan(origin: String, destination: String, lineIds: [String], durationSecs: Int) {
        client.send(.logRoutePlan(
            origin: origin,
            destination: destination,
            lineIds: lineIds,
            durationSecs: durationSecs
        ))
    }
}
```

Call this immediately after A* completes on-device:

```swift
AnalyticsService.shared.logRoutePlan(
    origin: "MRT3_NORTH_EDSA",
    destination: "MRT3_AYALA",
    lineIds: ["MRT3"],
    durationSecs: Int(routeDuration)
)
```

---

## Incident service

```swift
final class IncidentService {
    static let shared = IncidentService()
    private let client = APIClient.shared

    func activeIncidents() async throws -> [Incident] {
        let resp: APIResponse<[Incident]> = try await client.request(
            .incidents,
            responseType: APIResponse<[Incident]>.self
        )
        return resp.data
    }

    func report(stationId: String, description: String, category: String) async throws -> Incident {
        let resp: APIResponse<Incident> = try await client.request(
            .reportIncident(stationId: stationId, description: description, category: category),
            responseType: APIResponse<Incident>.self
        )
        return resp.data
    }
}
```

---

## Rate limits to respect

| Scope | Limit | Behaviour on exceed |
|---|---|---|
| Auth endpoints (by IP) | 10 req / 20 s | `429` |
| Sign-in by email | 5 req / 5 min | `429` |
| API endpoints (by IP) | 60 req / min | `429` |
| Analytics writes (by user) | 30 req / min | `429` — already fire-and-forget, so silently dropped |

Catch `APIError.tooManyRequests` and show a "Try again in a moment" message rather than retrying immediately.

---

## Error display reference

| `APIError` case | User-facing message |
|---|---|
| `.unauthorized` | "Session expired. Please sign in again." |
| `.forbidden` | "You don't have permission to do this." |
| `.notFound` | "This item no longer exists." |
| `.unprocessable(msg)` | Show `msg` directly (already human-readable from server) |
| `.tooManyRequests` | "Too many requests. Try again in a moment." |
| `.serverError` | "Something went wrong. Try again later." |
| `.network` | "Check your internet connection." |
| `.decodingFailed` | Log silently; show generic server error to user |
