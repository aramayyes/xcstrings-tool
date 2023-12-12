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
  let resourcesTree: Node

  init(tableName: String, accessLevel: AccessLevel, resources: [Resource]) {
    self.tableName = tableName
    self.accessLevel = accessLevel
    resourcesTree = Self.structure(resources: resources)
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
        generateNodeBlock(resourcesTree)
      }
    )
  }

  @MemberBlockItemListBuilder
  private func generateNodeBlock(_ node: Node) -> MemberBlockItemListSyntax {
    for child in node.children {
      EnumDeclSyntax(
        name: .identifier(child.name),
        memberBlockBuilder: {
          generateNodeBlock(child)
        }
      )
    }

    for resource in node.strings {
      resource.declaration(
        tableName: tableName,
        accessLevel: accessLevel.token
      )
    }
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

// MARK: Tree

private class Node {
  let name: String
  var strings: [Resource] = []
  var children: [Node] = []

  init(name: String, strings: [Resource] = [], children: [Node] = []) {
    self.name = name
    self.strings = strings
    self.children = children
  }
}

extension StringGenerator {
  private static func structure(
    resources: [Resource],
    atKeyPath keyPath: [String] = []
  ) -> Node {
    let root = Node(name: keyPath.last ?? "")

    // Collect strings for this level
    let strings = resources
      .filter { $0.keyComponents.count == keyPath.count + 1 }
      .sorted { $0.key.lowercased() < $1.key.lowercased() }

    if !strings.isEmpty {
      root.strings = strings
    }

    // collect children for this level, group them by name for the next level,
    // sort them and then structure those grouped resources
    let childResources = resources
      .filter { $0.keyComponents.count > keyPath.count + 1 }

    let children = Dictionary(grouping: childResources) {
      $0.keyComponents[keyPath.count]
    }
    .sorted { $0.key < $1.key }
    .map { name, resources in
      structure(
        resources: resources,
        atKeyPath: keyPath + [name]
      )
    }

    if !children.isEmpty {
      root.children = children
    }

    return root
  }
}
