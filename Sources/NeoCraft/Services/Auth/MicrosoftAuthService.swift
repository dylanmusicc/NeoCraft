import Foundation

actor MicrosoftAuthService {
    private let clientID: String

    init(clientID: String = AppConstants.msaClientID) {
        self.clientID = clientID
    }

    func requestDeviceCode() async throws -> DeviceCode {
        let url = try HTTPClient.url("\(AppConstants.microsoftAuthorizeBase)/devicecode")
        let response = try await HTTPClient.postForm(url, fields: [
            "client_id": clientID,
            "scope": "XboxLive.signin offline_access"
        ])
        let data = try HTTPClient.requireSuccess(response)
        do {
            return try JSONDecoder().decode(DeviceCode.self, from: data)
        } catch {
            throw AuthError.microsoftRejected(parseErrorMessage(data))
        }
    }

    func signIn(
        deviceCode: DeviceCode,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> (account: MinecraftAccount, auth: StoredAuth) {
        onStatus("Waiting for Microsoft authorization…")
        let msa = try await pollForToken(deviceCode: deviceCode)

        onStatus("Signing in to Xbox Live…")
        let xbox = try await xboxAuthenticate(msaAccessToken: msa.accessToken)

        onStatus("Authorizing Minecraft services…")
        let xsts = try await xstsAuthorize(xboxToken: xbox.token)

        onStatus("Connecting to Minecraft…")
        let minecraft = try await minecraftLogin(xuid: xbox.userHash, xstsToken: xsts.token)

        onStatus("Loading your profile…")
        let profile = try await fetchProfile(accessToken: minecraft.accessToken)

        let uuid = normalizeUUID(profile.id)
        let account = MinecraftAccount(
            uuid: uuid,
            name: profile.name,
            skinURL: profile.skins?.first.flatMap { URL(string: $0.url) },
            addedAt: Date(),
            lastUsed: Date()
        )

        let stored = StoredAuth(
            msaAccessToken: msa.accessToken,
            msaRefreshToken: msa.refreshToken,
            msaExpiresAt: msa.expiresAt,
            minecraftAccessToken: minecraft.accessToken,
            minecraftExpiresAt: minecraft.expiresAt,
            xuid: xbox.userHash,
            username: profile.name
        )

        try KeychainStore.save(stored, for: uuid)
        onStatus("Signed in as \(profile.name)")
        return (account, stored)
    }

    func validSession(for account: MinecraftAccount) async throws -> MinecraftSession {
        guard let stored = try KeychainStore.load(for: account.uuid) else {
            throw AuthError.reauthenticationRequired
        }

        let now = Date()
        if stored.minecraftExpiresAt.timeIntervalSince(now) > 120 {
            return MinecraftSession(
                accessToken: stored.minecraftAccessToken,
                uuid: account.uuid,
                name: account.name,
                xuid: stored.xuid,
                expiresAt: stored.minecraftExpiresAt
            )
        }

        var msaToken: MSAToken
        if stored.msaExpiresAt.timeIntervalSince(now) > 120 {
            msaToken = MSAToken(
                accessToken: stored.msaAccessToken,
                refreshToken: stored.msaRefreshToken,
                expiresAt: stored.msaExpiresAt
            )
        } else {
            do {
                msaToken = try await refreshMSA(refreshToken: stored.msaRefreshToken)
            } catch {
                KeychainStore.delete(for: account.uuid)
                throw AuthError.reauthenticationRequired
            }
        }

        let xbox = try await xboxAuthenticate(msaAccessToken: msaToken.accessToken)
        let xsts = try await xstsAuthorize(xboxToken: xbox.token)
        let minecraft = try await minecraftLogin(xuid: xbox.userHash, xstsToken: xsts.token)

        let refreshed = StoredAuth(
            msaAccessToken: msaToken.accessToken,
            msaRefreshToken: msaToken.refreshToken,
            msaExpiresAt: msaToken.expiresAt,
            minecraftAccessToken: minecraft.accessToken,
            minecraftExpiresAt: minecraft.expiresAt,
            xuid: xbox.userHash,
            username: stored.username
        )
        try KeychainStore.save(refreshed, for: account.uuid)

        return MinecraftSession(
            accessToken: minecraft.accessToken,
            uuid: account.uuid,
            name: account.name,
            xuid: xbox.userHash,
            expiresAt: minecraft.expiresAt
        )
    }

    func removeCredentials(for accountUUID: String) {
        KeychainStore.delete(for: accountUUID)
    }

    // MARK: - OAuth

    private func pollForToken(deviceCode: DeviceCode) async throws -> MSAToken {
        let url = try HTTPClient.url("\(AppConstants.microsoftAuthorizeBase)/token")
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(2, deviceCode.interval)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(interval))

            let response = try await HTTPClient.postForm(url, fields: [
                "client_id": clientID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": deviceCode.deviceCode
            ])

            if (200...299).contains(response.statusCode) {
                let token = try JSONDecoder().decode(MSATokenResponse.self, from: response.data)
                return MSAToken(
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken ?? "",
                    expiresAt: Date().addingTimeInterval(TimeInterval(max(60, token.expiresIn - 120)))
                )
            }

            let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: response.data)
            switch oauthError?.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "expired_token":
                throw AuthError.deviceCodeExpired
            case "authorization_declined", "access_denied":
                throw AuthError.authorizationDeclined
            case "bad_verification_code":
                throw AuthError.microsoftRejected("The code was not accepted. Start sign-in again to get a new code.")
            default:
                let detail = oauthError?.errorDescription ?? response.text
                throw AuthError.microsoftRejected(detail)
            }
        }
        throw AuthError.deviceCodeExpired
    }

    private func refreshMSA(refreshToken: String) async throws -> MSAToken {
        let url = try HTTPClient.url("\(AppConstants.microsoftAuthorizeBase)/token")
        let response = try await HTTPClient.postForm(url, fields: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "XboxLive.signin offline_access"
        ])
        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.http(status: response.statusCode, message: parseErrorMessage(response.data))
        }
        let token = try JSONDecoder().decode(MSATokenResponse.self, from: response.data)
        return MSAToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(60, token.expiresIn - 120)))
        )
    }

    // MARK: - Xbox

    private struct XBLRequest: Encodable {
        let Properties: XBLProperties
        let RelyingParty: String
        let TokenType: String
    }

    private struct XBLProperties: Encodable {
        let AuthMethod: String
        let SiteName: String
        let RpsTicket: String
    }

    private struct XSTSRequest: Encodable {
        let Properties: XSTSProperties
        let RelyingParty: String
        let TokenType: String
    }

    private struct XSTSProperties: Encodable {
        let SandboxId: String
        let UserTokens: [String]
    }

    private struct XBLResponse: Decodable {
        let token: String
        let displayClaims: XBLDisplayClaims

        enum CodingKeys: String, CodingKey {
            case token = "Token"
            case displayClaims = "DisplayClaims"
        }
    }

    private struct XBLDisplayClaims: Decodable {
        let xui: [XUI]

        struct XUI: Decodable {
            let uhs: String
        }
    }

    private struct XSTSErrorResponse: Decodable {
        let XErr: Int?
        let Message: String?
    }

    private struct XboxIdentity: Sendable {
        let token: String
        let userHash: String
    }

    private func xboxAuthenticate(msaAccessToken: String) async throws -> XboxIdentity {
        let url = try HTTPClient.url(AppConstants.xboxUserAuthURL)
        let headers = ["x-xbl-contract-version": "1"]

        let tickets = ["d=\(msaAccessToken)", msaAccessToken]
        var lastResponse: HTTPResponse?
        for ticket in tickets {
            let body = XBLRequest(
                Properties: XBLProperties(
                    AuthMethod: "RPS",
                    SiteName: "user.auth.xboxlive.com",
                    RpsTicket: ticket
                ),
                RelyingParty: "http://auth.xboxlive.com",
                TokenType: "JWT"
            )
            let response = try await HTTPClient.postJSON(url, body: body, headers: headers)
            lastResponse = response
            if (200...299).contains(response.statusCode) {
                let decoded = try JSONDecoder().decode(XBLResponse.self, from: response.data)
                guard let userHash = decoded.displayClaims.xui.first?.uhs else {
                    throw AuthError.invalidResponse
                }
                return XboxIdentity(token: decoded.token, userHash: userHash)
            }
            if response.statusCode != 400 {
                break
            }
        }
        throw AuthError.microsoftRejected(
            lastResponse.map { parseErrorMessage($0.data) } ?? "Xbox Live authentication failed."
        )
    }

    private func xstsAuthorize(xboxToken: String) async throws -> XboxIdentity {
        let url = try HTTPClient.url(AppConstants.xstsAuthURL)
        let body = XSTSRequest(
            Properties: XSTSProperties(SandboxId: "RETAIL", UserTokens: [xboxToken]),
            RelyingParty: "rp://api.minecraftservices.com/",
            TokenType: "JWT"
        )
        let response = try await HTTPClient.postJSON(
            url,
            body: body,
            headers: ["x-xbl-contract-version": "1"]
        )

        if (200...299).contains(response.statusCode) {
            let decoded = try JSONDecoder().decode(XBLResponse.self, from: response.data)
            guard let userHash = decoded.displayClaims.xui.first?.uhs else {
                throw AuthError.invalidResponse
            }
            return XboxIdentity(token: decoded.token, userHash: userHash)
        }

        let errorResponse = try? JSONDecoder().decode(XSTSErrorResponse.self, from: response.data)
        if let xerr = errorResponse?.XErr {
            switch xerr {
            case 2148916233:
                throw AuthError.noXboxProfile
            case 2148916235:
                throw AuthError.xboxRegionUnavailable
            case 2148916238:
                throw AuthError.childAccount
            case 2148916227, 2148916229:
                throw AuthError.xboxBanned
            default:
                throw AuthError.xboxError(
                    code: String(xerr),
                    message: errorResponse?.Message ?? "Please try again in a few minutes."
                )
            }
        }
        throw AuthError.microsoftRejected(parseErrorMessage(response.data))
    }

    // MARK: - Minecraft

    private struct MinecraftLoginRequest: Encodable {
        let identityToken: String
    }

    private struct MinecraftLoginResponse: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private struct MinecraftProfile: Decodable {
        let id: String
        let name: String
        let skins: [MinecraftSkin]?
    }

    private struct MinecraftSkin: Decodable {
        let id: String?
        let state: String?
        let url: String
        let variant: String?
    }

    private struct MinecraftToken: Sendable {
        let accessToken: String
        let expiresAt: Date
    }

    private func minecraftLogin(xuid: String, xstsToken: String) async throws -> MinecraftToken {
        let url = try HTTPClient.url(AppConstants.minecraftLoginURL)
        let body = MinecraftLoginRequest(identityToken: "XBL3.0 x=\(xuid);\(xstsToken)")
        let response = try await HTTPClient.postJSON(url, body: body)

        if response.statusCode == 401 || response.statusCode == 403 {
            throw AuthError.noGameOwnership
        }
        let data = try HTTPClient.requireSuccess(response)
        let token = try JSONDecoder().decode(MinecraftLoginResponse.self, from: data)
        return MinecraftToken(
            accessToken: token.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(60, token.expiresIn - 120)))
        )
    }

    private func fetchProfile(accessToken: String) async throws -> MinecraftProfile {
        let url = try HTTPClient.url(AppConstants.minecraftProfileURL)
        let response = try await HTTPClient.get(
            url,
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
        if response.statusCode == 404 {
            throw AuthError.noMinecraftProfile
        }
        if response.statusCode == 401 {
            throw AuthError.reauthenticationRequired
        }
        let data = try HTTPClient.requireSuccess(response)
        do {
            return try JSONDecoder().decode(MinecraftProfile.self, from: data)
        } catch {
            throw AuthError.invalidResponse
        }
    }

    private func normalizeUUID(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "-", with: "").lowercased()
        guard cleaned.count == 32 else { return raw }
        let groups = [cleaned.prefix(8),
                      cleaned.dropFirst(8).prefix(4),
                      cleaned.dropFirst(12).prefix(4),
                      cleaned.dropFirst(16).prefix(4),
                      cleaned.dropFirst(20)]
        return groups.joined(separator: "-")
    }

    private func parseErrorMessage(_ data: Data) -> String {
        if let oauth = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            return oauth.errorDescription ?? oauth.error
        }
        if let generic = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let description = generic["error_description"] as? String { return description }
            if let error = generic["error"] as? String { return error }
            if let message = generic["Message"] as? String { return message }
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MSATokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
