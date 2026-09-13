import Foundation

/// Compile-time / runtime guard for the Articles (rich text) backport.
/// Set `articles.enabled` in `UserDefaults` to `false` to disable without
/// affecting ordinary message send/receive.
public enum ArticlesFeature {
    public static var isEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: "articles.enabled") as? Bool {
            return value
        }
        return true
    }
}
