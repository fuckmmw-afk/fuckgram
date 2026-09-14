import Foundation
import Postbox
import SwiftSignalKit

// Compatibility accessors retained for Telegram 11.15 presentation modules.
// The layer-228 core stores chat themes as a richer enum that can also contain
// collectible gifts; the legacy UI only understands emoticon themes.

private func legacyThemeEmoticon(_ chatTheme: ChatTheme?) -> String? {
    if case let .emoticon(emoticon) = chatTheme {
        return emoticon
    } else {
        return nil
    }
}

public extension CachedChannelData {
    var themeEmoticon: String? {
        return legacyThemeEmoticon(self.chatTheme)
    }

    func withUpdatedThemeEmoticon(_ themeEmoticon: String?) -> CachedChannelData {
        return self.withUpdatedChatTheme(themeEmoticon.flatMap { .emoticon($0) })
    }
}

public extension CachedGroupData {
    var themeEmoticon: String? {
        return legacyThemeEmoticon(self.chatTheme)
    }

    func withUpdatedThemeEmoticon(_ themeEmoticon: String?) -> CachedGroupData {
        return self.withUpdatedChatTheme(themeEmoticon.flatMap { .emoticon($0) })
    }
}

public extension CachedUserData {
    var themeEmoticon: String? {
        return legacyThemeEmoticon(self.chatTheme)
    }

    func withUpdatedThemeEmoticon(_ themeEmoticon: String?) -> CachedUserData {
        return self.withUpdatedChatTheme(themeEmoticon.flatMap { .emoticon($0) })
    }
}

public extension PeerColor {
    var legacyPreset: PeerNameColor? {
        if case let .preset(value) = self {
            return value
        } else {
            return nil
        }
    }
}

public func addAppLogEvent(postbox: Postbox, time: Double = Date().timeIntervalSince1970, type: String, peerId: PeerId? = nil, data: JSON = .dictionary([:])) {
    _internal_addAppLogEvent(postbox: postbox, time: time, type: type, peerId: peerId, data: data)
}
