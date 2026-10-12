import Foundation

/// Конфигурация приложения. В iOS значения приходят из Info.plist, куда их подставляет
/// Xcode из `Config/*.xcconfig` (серверный .env в приложение НЕ попадает).
public struct AppConfiguration: Equatable, Sendable {
    public struct Supabase: Equatable, Sendable {
        public let url: URL
        /// Публичный (anon / publishable) ключ. Защищён политиками RLS. НЕ service_role!
        public let anonKey: String
    }

    public var supabase: Supabase?
    public var manifestURL: URL?
    public var demoCatalog: Bool
    public var testStreamsEnabledByDefault: Bool
    /// Партнёрский токен Kodik API (kodik.biz). Без него раздел «Озвучки онлайн» скрыт.
    public var kodikToken: String?
    /// Предупреждения конфигурации, которые стоит показать в настройках.
    public var warnings: [String]

    public init(supabase: Supabase? = nil, manifestURL: URL? = nil, demoCatalog: Bool = false,
                testStreamsEnabledByDefault: Bool = true, kodikToken: String? = nil, warnings: [String] = []) {
        self.supabase = supabase
        self.manifestURL = manifestURL
        self.demoCatalog = demoCatalog
        self.testStreamsEnabledByDefault = testStreamsEnabledByDefault
        self.kodikToken = kodikToken
        self.warnings = warnings
    }

    public enum Key {
        public static let supabaseURL = "AnivibeSupabaseURL"
        public static let supabaseAnonKey = "AnivibeSupabaseAnonKey"
        public static let manifestURL = "AnivibeManifestURL"
        public static let demoCatalog = "AnivibeDemoCatalog"
        public static let testStreams = "AnivibeTestStreams"
        public static let kodikToken = "AnivibeKodikToken"
    }

    /// Разбор словаря Info.plist. Пустые значения и нераскрытые `$(VAR)` считаются «не задано».
    public static func from(infoDictionary info: [String: Any]) -> AppConfiguration {
        var warnings: [String] = []

        func string(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v.hasPrefix("$(") || v.contains("YOUR_") || v.contains("your-project") { return nil }
            return v
        }
        func bool(_ key: String, default def: Bool) -> Bool {
            guard let s = string(key)?.lowercased() else { return def }
            return ["yes", "true", "1"].contains(s)
        }

        var supabase: Supabase?
        let rawURL = string(Key.supabaseURL)
        let rawKey = string(Key.supabaseAnonKey)
        switch (rawURL, rawKey) {
        case let (u?, k?):
            if let url = validatedURL(u) {
                if looksLikeServiceRoleKey(k) {
                    warnings.append("В приложение передан service_role-ключ Supabase. Он отклонён: используйте только anon/publishable-ключ.")
                } else {
                    supabase = Supabase(url: url, anonKey: k)
                }
            } else {
                warnings.append("ANIVIBE_SUPABASE_URL некорректен (нужен https://…, http допускается только для localhost).")
            }
        case (nil, nil):
            break
        default:
            warnings.append("Supabase настроен частично: нужны и URL, и anon-ключ. Работает локальный режим.")
        }

        var manifest: URL?
        if let m = string(Key.manifestURL) {
            if let url = validatedURL(m), url.scheme == "https" { manifest = url } else {
                warnings.append("ANIVIBE_MANIFEST_URL должен быть https-ссылкой.")
            }
        }

        return AppConfiguration(supabase: supabase, manifestURL: manifest,
                                demoCatalog: bool(Key.demoCatalog, default: false),
                                testStreamsEnabledByDefault: bool(Key.testStreams, default: true),
                                kodikToken: string(Key.kodikToken),
                                warnings: warnings)
    }

    static func validatedURL(_ s: String) -> URL? {
        guard let comps = URLComponents(string: s), let host = comps.host, !host.isEmpty, let url = comps.url else { return nil }
        if comps.scheme == "https" { return url }
        if comps.scheme == "http", ["localhost", "127.0.0.1"].contains(host) { return url }
        return nil
    }

    /// Ключ service_role — JWT с ролью service_role или новый формат `sb_secret_…`.
    static func looksLikeServiceRoleKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["role"] as? String) == "service_role"
    }

    public var isSyncConfigured: Bool { supabase != nil }
}
