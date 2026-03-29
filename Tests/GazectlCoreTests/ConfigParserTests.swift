import Testing
@testable import GazectlCore

struct ConfigParserTests {
    @Test
    func parsesDefaultRunConfig() throws {
        let command = try ConfigParser.parse(arguments: ["gazectl"])

        #expect(command == .run(Config()))
    }

    @Test
    func parsesAirPodsSource() throws {
        let command = try ConfigParser.parse(arguments: ["gazectl", "--source", "airpods", "--verbose"])

        guard case .run(let config) = command else {
            Issue.record("Expected a run command")
            return
        }

        #expect(config.source == .airpods)
        #expect(config.verbose)
    }

    @Test
    func rejectsCameraFlagForAirPods() throws {
        #expect(throws: ConfigParseError.cameraOptionRequiresCameraSource) {
            try ConfigParser.parse(arguments: ["gazectl", "--source", "airpods", "--camera", "1"])
        }
    }
}
