import Foundation
import AuthenticationServices
import AppKit

/// Drives the OAuth 2.1 authorization-code + PKCE flow against Hadron's AS
/// (spec `cor:aut:030:01`): discovery → dynamic client registration →
/// `ASWebAuthenticationSession` consent → token exchange. Returns a long-lived
/// `hdr_user_*` bearer token usable on `/graphql`.
@MainActor
final class OAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum OAuthError: LocalizedError {
        case discoveryFailed
        case registrationFailed(String)
        case authorizationFailed(String)
        case userCancelled
        case stateMismatch
        case missingCode
        case tokenExchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .discoveryFailed: return "Couldn't reach the Hadron sign-in service."
            case .registrationFailed(let m): return "Client registration failed: \(m)"
            case .authorizationFailed(let m): return "Authorization failed: \(m)"
            case .userCancelled: return "Sign-in was cancelled."
            case .stateMismatch: return "Sign-in failed a security check (state mismatch)."
            case .missingCode: return "Sign-in didn't return an authorization code."
            case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
            }
        }
    }

    private struct ASMetadata: Decodable {
        let authorization_endpoint: String
        let token_endpoint: String
        let registration_endpoint: String?
    }
    private struct RegistrationResponse: Decodable { let client_id: String }
    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let scope: String?
    }

    /// Retained for the lifetime of the browser session.
    private var webAuthSession: ASWebAuthenticationSession?

    // MARK: - Public entry point

    /// Run the full flow and return the issued access token.
    func authenticate() async throws -> String {
        let metadata = try await fetchMetadata()
        let clientId = try await ensureClientId(registrationEndpoint: metadata.registration_endpoint)

        let pkce = PKCEPair()
        let state = UUID().uuidString
        let authURL = buildAuthorizeURL(
            endpoint: metadata.authorization_endpoint,
            clientId: clientId,
            pkce: pkce,
            state: state
        )

        let callbackURL = try await runWebAuth(url: authURL)
        let (code, returnedState) = try parseCallback(callbackURL)
        guard returnedState == state else { throw OAuthError.stateMismatch }

        return try await exchangeToken(
            endpoint: metadata.token_endpoint,
            code: code,
            clientId: clientId,
            verifier: pkce.codeVerifier
        )
    }

    // MARK: - Steps

    private func fetchMetadata() async throws -> ASMetadata {
        let url = HadronConfig.baseURL.appendingPathComponent(".well-known/oauth-authorization-server")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw OAuthError.discoveryFailed
            }
            return try JSONDecoder().decode(ASMetadata.self, from: data)
        } catch let e as OAuthError {
            throw e
        } catch {
            throw OAuthError.discoveryFailed
        }
    }

    /// Reuse a cached client id, else dynamically register one and cache it.
    private func ensureClientId(registrationEndpoint: String?) async throws -> String {
        if let cached = KeychainStore.get(.clientId) { return cached }

        let endpoint = registrationEndpoint.flatMap(URL.init(string:))
            ?? HadronConfig.baseURL.appendingPathComponent("oauth/register")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "redirect_uris": [HadronConfig.redirectURI],
            "client_name": HadronConfig.clientName,
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code"],
            "response_types": ["code"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw OAuthError.registrationFailed(Self.errorText(data, status))
        }
        let decoded = try JSONDecoder().decode(RegistrationResponse.self, from: data)
        KeychainStore.set(decoded.client_id, for: .clientId)
        return decoded.client_id
    }

    private func buildAuthorizeURL(endpoint: String, clientId: String, pkce: PKCEPair, state: String) -> URL {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: HadronConfig.redirectURI),
            .init(name: "scope", value: HadronConfig.scope),
            .init(name: "resource", value: HadronConfig.resource),
            .init(name: "code_challenge", value: pkce.codeChallenge),
            .init(name: "code_challenge_method", value: pkce.method),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    private func runWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: HadronConfig.callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authorizationFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.authorizationFailed("Couldn't start the sign-in session."))
            }
        }
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw OAuthError.authorizationFailed(description)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        return (code, items.first(where: { $0.name == "state" })?.value)
    }

    private func exchangeToken(endpoint: String, code: String, clientId: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let form: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": HadronConfig.redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
            "resource": HadronConfig.resource,
        ]
        request.httpBody = Self.formURLEncoded(form).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OAuthError.tokenExchangeFailed(Self.errorText(data, status))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
    }

    // MARK: - Helpers

    private static func formURLEncoded(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private static func errorText(_ data: Data, _ status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let description = json["error_description"] as? String { return description }
            if let error = json["error"] as? String { return error }
        }
        return "HTTP \(status)"
    }
}
