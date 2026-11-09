import Foundation

/// Resolves against the app bundle, whose `Localizable.xcstrings` holds every user-facing string.
public func L(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, defaultValue: defaultValue, table: nil, bundle: .main)
}
