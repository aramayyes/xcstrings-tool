import Foundation
import RegexBuilder

/// A helper for parsing a string value within a string catalog to extract
/// placeholder and substitution markers
struct StringParser {
  enum ParsedSegment: Equatable {
    case string(contents: String)
    case placeholder(PlaceholderType, specifier: String, position: Int?)
  }

  /// Parse the given input string including the expansion of the given
  /// substitutions
  static func parse(
    _ input: String,
    expandingSubstitutions substitutions: [String: String]
  ) -> [ParsedSegment] {
    var input = input
    for (key, value) in substitutions {
      input = input.replacingOccurrences(of: "%#@\(key)@", with: value)
    }

    return parse(input)
  }

  /// Parses the given input string into an array of segments
  private static func parse(_ input: String) -> [ParsedSegment] {
    var segments: [ParsedSegment] = []
    var lastIndex = input.startIndex

    for match in input.matches(of: regex) {
      var string: String?
      if match.range.lowerBound != lastIndex {
        string = String(input[lastIndex ..< match.range.lowerBound])
      }

      let output: (
        matchedString: Substring,
        position: Int?,
        placeholder: PlaceholderType
      ) = match.output

      if let string, !string.reversed().prefix(while: { $0 == "%" }).count
        .isMultiple(of: 2) // %%
      {
        segments.append(
          .string(contents: string.appending(output.matchedString))
        )
      } else {
        if let string {
          segments.append(.string(contents: string))
        }
        segments
          .append(.placeholder(
            output.placeholder,
            specifier: String(output.matchedString),
            position: output.position
          ))
      }

      lastIndex = match.range.upperBound
    }

    // If there was more content after the last match, append it to the final
    // output
    if input.endIndex != lastIndex {
      let string = String(input[lastIndex ..< input.endIndex])
      segments.append(.string(contents: string))
    }

    return segments
  }
}

extension StringParser {
  static let regex = Regex {
    // The start of the specifier
    "%"

    // Optional, positional information
    Optionally {
      TryCapture {
        OneOrMore(.digit)
      } transform: { rawValue in
        Int(rawValue)
      }
      "$"
    }

    // Optional, precision information
    Optionally(.anyOf("-+# 0"))
    Optionally(.digit)
    Optionally {
      "."
      One(.digit)
    }

    // Required, the format (inc lengths)
    TryCapture {
      ChoiceOf {
        "@"
        Regex {
          Optionally {
            ChoiceOf {
              "h"
              "hh"
              "l"
              "ll"
              "q"
              "z"
              "t"
              "j"
            }
          }
          One(.anyOf("dioux"))
        }
        One(.anyOf("aefg"))
        One(.anyOf("csp"))
      }
    } transform: { rawValue -> PlaceholderType? in
      PlaceholderType(formatSpecifier: rawValue)
    }
  }
}
