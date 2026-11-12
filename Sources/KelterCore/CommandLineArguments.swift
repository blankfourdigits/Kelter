import Foundation

/// Converts between a line of text typed by the user and a list of
/// arguments. Double quotes group words; backslashes are ordinary characters
/// because Windows paths are full of them.
public enum CommandLineArguments {
    public static func split(_ text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var hasToken = false
        var inQuotes = false

        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                // `""` is an empty argument.
                hasToken = true
            } else if character.isWhitespace && !inQuotes {
                if hasToken {
                    arguments.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken {
            arguments.append(current)
        }
        return arguments
    }

    public static func join(_ arguments: [String]) -> String {
        arguments
            .map { argument in
                let needsQuotes = argument.isEmpty || argument.contains(where: { $0.isWhitespace })
                return needsQuotes ? "\"\(argument)\"" : argument
            }
            .joined(separator: " ")
    }
}
