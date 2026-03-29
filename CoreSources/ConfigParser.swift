import Foundation

public struct Config: Equatable, Sendable {
    public var calibrate = false
    public var calibrationFile: String
    public var cameraIndex = 0
    public var verbose = false
    public var debug = false
    public var source: TrackingSource = .camera

    public static let defaultCalibrationPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/share/gazectl/calibration.json"
    }()

    public init() {
        calibrationFile = Self.defaultCalibrationPath
    }
}

public enum ParsedCommand: Equatable, Sendable {
    case run(Config)
    case help
    case version
}

public enum ConfigParseError: Error, Equatable, CustomStringConvertible {
    case missingValue(flag: String)
    case invalidInteger(flag: String, value: String)
    case invalidSource(String)
    case cameraOptionRequiresCameraSource
    case unknownArgument(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .invalidInteger(let flag, let value):
            return "\(flag) requires an integer, got \(value)"
        case .invalidSource(let source):
            return "Invalid source '\(source)'. Use 'camera' or 'airpods'."
        case .cameraOptionRequiresCameraSource:
            return "--camera can only be used with --source camera"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

public enum ConfigParser {
    public static func parse(arguments: [String]) throws -> ParsedCommand {
        var config = Config()
        var args = Array(arguments.dropFirst())
        var cameraSpecified = false

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--calibrate":
                config.calibrate = true
            case "--calibration-file":
                guard !args.isEmpty else {
                    throw ConfigParseError.missingValue(flag: "--calibration-file")
                }
                config.calibrationFile = args.removeFirst()
            case "--camera":
                guard !args.isEmpty else {
                    throw ConfigParseError.missingValue(flag: "--camera")
                }
                let value = args.removeFirst()
                guard let index = Int(value) else {
                    throw ConfigParseError.invalidInteger(flag: "--camera", value: value)
                }
                config.cameraIndex = index
                cameraSpecified = true
            case "--source":
                guard !args.isEmpty else {
                    throw ConfigParseError.missingValue(flag: "--source")
                }
                let value = args.removeFirst()
                guard let source = TrackingSource(rawValue: value.lowercased()) else {
                    throw ConfigParseError.invalidSource(value)
                }
                config.source = source
            case "--verbose":
                config.verbose = true
            case "--debug":
                config.debug = true
            case "-v", "--version":
                return .version
            case "-h", "--help":
                return .help
            default:
                throw ConfigParseError.unknownArgument(arg)
            }
        }

        if cameraSpecified && config.source != .camera {
            throw ConfigParseError.cameraOptionRequiresCameraSource
        }

        return .run(config)
    }
}
