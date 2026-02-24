import Foundation
import Security

protocol APITokenStoring: AnyObject {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func deleteToken()
}

final class KeychainAPITokenStore: APITokenStoring {
    private let service: String
    private let account: String

    init(
        service: String = KeychainAPITokenStore.defaultServiceName(),
        account: String = "openai-api-token"
    ) {
        self.service = service
        self.account = account
    }

    func loadToken() -> String? {
        loadToken(using: service)
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteToken()
            return
        }

        guard let data = trimmed.data(using: .utf8) else { return }

        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            return
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    func deleteToken() {
        _ = SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        baseQuery(service: service)
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func loadToken(using service: String) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }

        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    private static func defaultServiceName() -> String {
        if let bundleID = Bundle.main.bundleIdentifier, bundleID.isEmpty == false {
            return bundleID + ".credentials"
        }
        return "RealTimeCaptionsTranslator.credentials"
    }
}
