import Foundation

public enum StringSegment: Equatable {
  case string(String)
  case interpolation(String, String)

  public var content: String {
    switch self {
    case let .string(string): string
    case let .interpolation(string, _): string
    }
  }

  public var contentWithSpecifier: String {
    switch self {
    case let .string(string): string
    case let .interpolation(_, string): string
    }
  }
}
