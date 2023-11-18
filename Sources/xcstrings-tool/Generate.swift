import ArgumentParser
import Foundation
import StringCatalog
import StringExtractor
import StringGenerator
import struct StringResource.Resource
import StringValidator

struct Generate: ParsableCommand {
  @Argument(
    help: "Path to xcstrings String Catalog file",
    completion: .file(extensions: ["xcstrings"]),
    transform: { URL(filePath: $0, directoryHint: .notDirectory) }
  )
  var input

  @Argument(
    help: "Path to write generated Swift code",
    completion: .file(extensions: ["swift"]),
    transform: { URL(filePath: $0, directoryHint: .notDirectory) }
  )
  var output

  @Option(
    name: .shortAndLong,
    help: "Path to difference xcstrings String Catalog file",
    transform: { string in
      string.isEmpty ? [] : string.components(separatedBy: .whitespaces).map {
        URL(filePath: $0, directoryHint: .notDirectory)
      }
    }
  )
  var diffsInputs: [URL] = []

  @Option(
    name: .shortAndLong,
    help: "Path to write generated difference Swift code",
    transform: { string in
      string.isEmpty ? [] : string.components(separatedBy: .whitespaces).map {
        URL(filePath: $0, directoryHint: .notDirectory)
      }
    }
  )
  var diffsOutputs: [URL] = []

  @Option(
    name: .shortAndLong,
    help: "Modify the Access Control for the generated source code"
  )
  var accessLevel: StringGenerator.AccessLevel?

  // MARK: - Program

  func run() throws {
    let mainCatalog = try withThrownErrorsAsDiagnostics(at: input) {
      try StringCatalog(contentsOf: input)
    }

    let mainResult = try withThrownErrorsAsDiagnostics(at: input) {
      try StringExtractor.extractResources(from: mainCatalog)
    }

    let mainSource = try withThrownErrorsAsDiagnostics(at: input) {
      // Validate the extraction result
      mainResult.issues.forEach { warning($0.description, sourceFile: input) }
      try ResourceValidator.validateResources(mainResult.resources, in: input)

      // Generate the associated Swift source
      return StringGenerator.generateSource(
        for: mainResult.resources,
        tableName: tableName,
        accessLevel: resolvedAccessLevel
      )
    }

    try withThrownErrorsAsDiagnostics {
      try createDirectoryIfNeeded(for: output)

      try mainSource.write(to: output, atomically: true, encoding: .utf8)
      note("Output written to ‘\(output.path(percentEncoded: false))‘")
    }

    // Diffs generating.

    let mainResultKeys = try withThrownErrorsAsDiagnostics(at: input) {
      Set(mainResult.resources.map(\.key))
    }
    for (diffsInput, diffsOutput) in zip(diffsInputs, diffsOutputs) {
      let source = try withThrownErrorsAsDiagnostics(at: diffsInput) {
        try generateSource(
          mainResultKeys: mainResultKeys,
          diffsInput: diffsInput
        )
      }

      try withThrownErrorsAsDiagnostics {
        try createDirectoryIfNeeded(for: diffsOutput)

        try source.write(to: diffsOutput, atomically: true, encoding: .utf8)
        note("Output written to ‘\(diffsOutput.path(percentEncoded: false))‘")
      }
    }
  }

  func generateSource(
    mainResultKeys: Set<String>,
    diffsInput: URL
  ) throws -> String {
    let diffsCatalog = try StringCatalog(contentsOf: diffsInput)
    let diffsResult = try StringExtractor.extractResources(from: diffsCatalog)

    let result: StringExtractor.Result = (
      diffsResult.resources
        .filter { resource in
          !mainResultKeys.contains { key in resource.key == key }
        },
      issues: diffsResult.issues
    )

    // Validate the extraction result
    result.issues.forEach { warning($0.description, sourceFile: input) }
    try ResourceValidator.validateResources(result.resources, in: input)

    // Generate the associated Swift source
    return StringGenerator.generateSource(
      for: result.resources,
      tableName: tableName,
      accessLevel: resolvedAccessLevel
    )
  }

  var tableName: String {
    input.lastPathComponent.replacingOccurrences(
      of: ".\(input.pathExtension)",
      with: ""
    )
  }

  var resolvedAccessLevel: StringGenerator.AccessLevel {
    .resolveFromEnvironment(or: accessLevel) ?? .internal
  }
}
