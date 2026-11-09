import Foundation

/// Short curated list of distinctive adware/PUP family names. Matched case-insensitively as whole tokens
/// of the label, the program file name and its enclosing `.app` name (never substrings, never directories).
/// Contributors can extend it; avoid names that are ordinary words.
public enum KnownAdware {
    public static let names: [String] = [
        "mughthesec", "pirrit", "genieo", "vsearch", "shlayer", "bundlore", "adload", "mackeeper",
        "crossrider", "searchmine", "installmac", "advancedmaccleaner",
    ]
}
