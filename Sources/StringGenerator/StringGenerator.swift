import Foundation
import StringResource
import SwiftBasicFormat
import SwiftIdentifier
import SwiftSyntax
import SwiftSyntaxBuilder

public struct StringGenerator {
  public enum AccessLevel: String, CaseIterable {
    case `internal`
    case `public`
    case package
  }

  let tableName: String
  let accessLevel: AccessLevel
  let resources: [Resource]

  init(tableName: String, accessLevel: AccessLevel, resources: [Resource]) {
    self.tableName = tableName
    self.accessLevel = accessLevel
    self.resources = resources
  }

  public static func generateSource(
    for resources: [Resource],
    tableName: String,
    accessLevel: AccessLevel
  ) -> String {
    StringGenerator(
      tableName: tableName,
      accessLevel: accessLevel,
      resources: resources
    )
    .generate()
    .formatted(using: .init(indentationWidth: .spaces(2)))
    .description
  }

  func generate() -> SourceFileSyntax {
    SourceFileSyntax {
      generateImports()
        .with(\.trailingTrivia, .newlines(2))

      generateLocalizedStringResourceExtension()
        .with(\.trailingTrivia, [
          .newlines(2),
          .lineComment("// swiftlint:enable all"),
        ])
    }
  }

  // MARK: - Source File Contents

  func generateImports() -> ImportDeclSyntax {
    ImportDeclSyntax(
      leadingTrivia: [
        .lineComment("// swiftlint:disable all"),
        .newlines(2),
        .lineComment("// Generated using xcstring-tool"),
        .newlines(2),
      ],
      path: [
        ImportPathComponentSyntax(
          name: .identifier("Foundation")
        ),
      ]
    )
  }

  func generateLocalizedStringResourceExtension() -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
      extendedType: IdentifierTypeSyntax(name: "LocalizationKey"),
      memberBlockBuilder: {
        for resource in resources {
          resource.declaration(
            tableName: tableName,
            accessLevel: accessLevel.token
          )
        }
      }
    )
  }

  // MARK: - Helpers

  var typeDocumentation: Trivia {
    let exampleResource = resources.first(where: { $0.arguments.isEmpty })
    let exampleId = exampleResource?.identifier ?? "foo"
    let exampleValue = exampleResource?.defaultValue.first?.content ?? "bar"
    let exampleAccessor = ".\(variableToken.text).\(exampleId)"

    return [
      .docLineComment(
        "/// Constant values for the \(tableName) Strings Catalog"
      ),
      .newlines(1),
      .docLineComment("///"),
      .newlines(1),
      .docLineComment("/// ```swift"),
      .newlines(1),
      .docLineComment("/// // Accessing the localized value directly"),
      .newlines(1),
      .docLineComment(
        "/// let value = String(localized: \(exampleAccessor))"
      ),
      .newlines(1),
      .docLineComment(
        "/// value // \"\(exampleValue.replacingOccurrences(of: "\n", with: "\\n"))\""
      ),
      .newlines(1),
      .docLineComment("///"),
      .newlines(1),
      .docLineComment("/// // Working with SwiftUI"),
      .newlines(1),
      .docLineComment("/// Text(\(exampleAccessor))"),
      .newlines(1),
      .docLineComment("/// ```"),
      .newlines(1),
    ]
  }

  var structToken: TokenSyntax {
    .identifier(SwiftIdentifier.identifier(from: tableName))
  }

  var variableToken: TokenSyntax {
    .identifier(SwiftIdentifier.variableIdentifier(for: tableName))
  }

  var bundleToken: TokenSyntax {
    .identifier("bundleDescription")
  }
}

extension StringGenerator.AccessLevel {
  var token: TokenSyntax {
    switch self {
    case .internal: .keyword(.internal)
    case .public: .keyword(.public)
    case .package: .keyword(.package)
    }
  }
}

extension Resource {
  func declaration(
    tableName: String,
    accessLevel: TokenSyntax
  ) -> DeclSyntaxProtocol {
    if arguments.isEmpty {
      VariableDeclSyntax(
        leadingTrivia: leadingTrivia,
        modifiers: [
          DeclModifierSyntax(name: accessLevel),
          DeclModifierSyntax(name: .keyword(.static)),
        ],
        bindingSpecifier: .keyword(.var),
        bindings: [
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: name),
            typeAnnotation: TypeAnnotationSyntax(type: type),
            accessorBlock: AccessorBlockSyntax(
              accessors: .getter(statements(table: tableName))
            )
          ),
        ]
      )
    } else {
      FunctionDeclSyntax(
        leadingTrivia: leadingTrivia,
        modifiers: [
          DeclModifierSyntax(name: accessLevel),
          DeclModifierSyntax(name: .keyword(.static)),
        ],
        name: name,
        signature: FunctionSignatureSyntax(
          parameterClause: FunctionParameterClauseSyntax(
            parameters: FunctionParameterListSyntax {
              for (idx, argument) in zip(1..., arguments) {
                if idx == arguments.count {
                  argument.parameter
                } else {
                  argument.parameter.with(
                    \.trailingComma,
                    .commaToken()
                  )
                }
              }
            }
          ),
          returnClause: ReturnClauseSyntax(type: type)
        ),
        body: CodeBlockSyntax(statements: statements(table: tableName))
      )
    }
  }

  var name: TokenSyntax {
    .identifier(identifier)
  }

  var type: IdentifierTypeSyntax {
    IdentifierTypeSyntax(name: .identifier("LocalizationKey"))
  }

  var leadingTrivia: Trivia {
    var trivia: Trivia = .newlines(2)

    let commentLines = defaultValue
      .map(\.contentWithSpecifier)
      .joined()
      .components(separatedBy: .newlines)

    if !commentLines.isEmpty {
      for line in commentLines {
        trivia = trivia.appending(Trivia.docLineComment("/// \(line)"))
        trivia = trivia.appending(.newline)
      }
    }

    return trivia
  }

  func statements(table: String) -> CodeBlockItemListSyntax {
    CodeBlockItemListSyntax {
      CodeBlockItemSyntax(
        item: .expr(
          ExprSyntax(
            FunctionCallExprSyntax(
              calledExpression: DeclReferenceExprSyntax(
                baseName: .identifier("LocalizationKey")
              ),
              leftParen: .leftParenToken(),
              arguments: arguments.isEmpty ?
                [
                  LabeledExprSyntax(
                    label: nil,
                    expression: keyExpr
                  ),
                ]
                :
                [
                  LabeledExprSyntax(
                    label: nil,
                    expression: keyExpr
                  )
                  .with(\.trailingComma, .commaToken()),

                  LabeledExprSyntax(
                    label: "arguments",
                    expression: ArrayExprSyntax(
                      elements: ArrayElementListSyntax {
                        for argument in arguments {
                          argument.arrayItem
                        }
                      }
                    )
                  ),
                ],
              rightParen: .rightParenToken()
            )
          )
        )
      )
    }
  }

  var keyExpr: StringLiteralExprSyntax {
    StringLiteralExprSyntax(content: key)
  }
}

extension Argument {
  var parameter: FunctionParameterSyntax {
    FunctionParameterSyntax(
      firstName: label.flatMap { .identifier($0) } ?? .wildcardToken(),
      secondName: .identifier(name),
      type: IdentifierTypeSyntax(name: .identifier(type))
    )
  }

  var arrayItem: ArrayElementSyntax {
    .init(expression: DeclReferenceExprSyntax(baseName: .identifier(name)))
  }
}

extension StringSegment {
  var element: StringLiteralSegmentListSyntax.Element {
    switch self {
    case let .string(content):
      return .stringSegment(
        StringSegmentSyntax(
          content: .stringSegment(
            content.escapingForStringLiteral(
              usingDelimiter: "###",
              isMultiline: false
            )
          )
        )
      )
    case let .interpolation(identifier, _):
      return .expressionSegment(
        ExpressionSegmentSyntax(
          pounds: .rawStringPoundDelimiter("###"),
          expressions: [
            LabeledExprSyntax(
              expression: DeclReferenceExprSyntax(
                baseName: .identifier(identifier)
              )
            ),
          ]
        )
      )
    }
  }
}

// Taken from inside SwiftSyntax
private extension String {
  /// Replace literal newlines with "\r", "\n", "\u{2028}", and ASCII control
  /// characters with "\0", "\u{7}"
  func escapingForStringLiteral(
    usingDelimiter delimiter: String,
    isMultiline: Bool
  ) -> String {
    // String literals cannot contain "unprintable" ASCII characters (control
    // characters, etc.) besides tab. As a matter of style, we also choose to
    // escape Unicode newlines like "\u{2028}" even though swiftc will allow
    // them in string literals.
    func needsEscaping(_ scalar: UnicodeScalar) -> Bool {
      if Character(scalar).isNewline {
        return true
      }

      if !scalar.isASCII || scalar.isPrintableASCII {
        return false
      }

      if scalar == "\t" {
        // Tabs need to be escaped in single-line string literals but not
        // multi-line string literals.
        return !isMultiline
      }
      return true
    }

    // Work at the Unicode scalar level so that "\r\n" isn't combined.
    var result = String.UnicodeScalarView()
    var input = unicodeScalars[...]
    while let firstNewline = input.firstIndex(where: needsEscaping(_:)) {
      result += input[..<firstNewline]

      result += "\\\(delimiter)".unicodeScalars
      switch input[firstNewline] {
      case "\r":
        result += "r".unicodeScalars
      case "\n":
        result += "n".unicodeScalars
      case "\t":
        result += "t".unicodeScalars
      case "\0":
        result += "0".unicodeScalars
      case let other:
        result += "u{\(String(other.value, radix: 16))}".unicodeScalars
      }
      input = input[input.index(after: firstNewline)...]
    }
    result += input

    return String(result)
  }
}

private extension Unicode.Scalar {
  /// Whether this character represents a printable ASCII character,
  /// for the purposes of pattern parsing.
  var isPrintableASCII: Bool {
    // Exclude non-printables before the space character U+20, and anything
    // including and above the DEL character U+7F.
    value >= 0x20 && value < 0x7F
  }
}
