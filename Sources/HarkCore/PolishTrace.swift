import Foundation

/// What happened to one dictation's polish: which path produced the paste, how each
/// contender in the race did, and how long things took. Holds timings, outcomes and error
/// types only, never what was said.
public struct PolishTrace: Codable, Equatable {
    public enum Path: String, Codable { case server, onDevice, rules }
    public enum Skip: String, Codable { case shift, settingOff, tooShort, noModel }
    public enum Outcome: String, Codable { case answered, rejected, error, deadline, notStarted, running, cancelled }

    public struct Contender: Codable, Equatable {
        public var name: String
        public var outcome: Outcome
        public var milliseconds: Int
        public var detail: String?
        public var revertedRegions: Int

        public init(name: String, outcome: Outcome, milliseconds: Int, detail: String? = nil, revertedRegions: Int = 0) {
            self.name = name
            self.outcome = outcome
            self.milliseconds = milliseconds
            self.detail = detail
            self.revertedRegions = revertedRegions
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            outcome = try values.decode(Outcome.self, forKey: .outcome)
            milliseconds = try values.decodeIfPresent(Int.self, forKey: .milliseconds) ?? 0
            detail = try values.decodeIfPresent(String.self, forKey: .detail)
            revertedRegions = try values.decodeIfPresent(Int.self, forKey: .revertedRegions) ?? 0
        }
    }

    /// Bumped by every change that alters pipeline output, so history can be split by
    /// version. 1: the trace itself.
    public static let currentPipelineVersion = 1

    public var entryID: UUID
    public var winner: Path
    public var skipped: Skip?
    public var shiftFlipped: Bool
    public var totalMilliseconds: Int
    public var contenders: [Contender]
    public var serverModel: String?
    public var transcribeMilliseconds: Int
    public var orphanInFlight: Bool
    public var learnedIDs: [UUID]
    public var pipelineVersion: Int
    /// A line written after the paste, carrying one contender's real outcome.
    public var late: Bool

    public init(
        entryID: UUID, winner: Path, skipped: Skip? = nil, shiftFlipped: Bool = false,
        totalMilliseconds: Int = 0, contenders: [Contender] = [], serverModel: String? = nil,
        transcribeMilliseconds: Int = 0, orphanInFlight: Bool = false, learnedIDs: [UUID] = [],
        pipelineVersion: Int = PolishTrace.currentPipelineVersion, late: Bool = false
    ) {
        self.entryID = entryID
        self.winner = winner
        self.skipped = skipped
        self.shiftFlipped = shiftFlipped
        self.totalMilliseconds = totalMilliseconds
        self.contenders = contenders
        self.serverModel = serverModel
        self.transcribeMilliseconds = transcribeMilliseconds
        self.orphanInFlight = orphanInFlight
        self.learnedIDs = learnedIDs
        self.pipelineVersion = pipelineVersion
        self.late = late
    }

    /// Only `entryID`, `winner` and `contenders` are required, so lines written by any
    /// earlier version still decode.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entryID = try values.decode(UUID.self, forKey: .entryID)
        winner = try values.decode(Path.self, forKey: .winner)
        contenders = try values.decode([Contender].self, forKey: .contenders)
        skipped = try values.decodeIfPresent(Skip.self, forKey: .skipped)
        shiftFlipped = try values.decodeIfPresent(Bool.self, forKey: .shiftFlipped) ?? false
        totalMilliseconds = try values.decodeIfPresent(Int.self, forKey: .totalMilliseconds) ?? 0
        serverModel = try values.decodeIfPresent(String.self, forKey: .serverModel)
        transcribeMilliseconds = try values.decodeIfPresent(Int.self, forKey: .transcribeMilliseconds) ?? 0
        orphanInFlight = try values.decodeIfPresent(Bool.self, forKey: .orphanInFlight) ?? false
        learnedIDs = try values.decodeIfPresent([UUID].self, forKey: .learnedIDs) ?? []
        pipelineVersion = try values.decodeIfPresent(Int.self, forKey: .pipelineVersion) ?? 0
        late = try values.decodeIfPresent(Bool.self, forKey: .late) ?? false
    }
}
