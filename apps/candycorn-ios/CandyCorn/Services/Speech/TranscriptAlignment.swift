import Foundation

struct TranscriptAlignmentInput: Sendable {
    let appointmentID: UUID
    let transcript: TranscriptResult
    let diarization: DiarizationResult
    let assignments: [SpeakerClusterAssignment]
    let patientVoiceProfiles: [PatientVoiceProfile]
}

protocol TranscriptAligning: Sendable {
    func align(_ input: TranscriptAlignmentInput) throws -> [TranscriptSegment]
}

enum TranscriptAlignmentError: Error, Equatable, Sendable {
    case emptyTranscript
    case emptyDiarization
    case inputLimitExceeded
    case missingTimestamp(pieceIndex: Int)
    case invalidTranscriptRange(pieceIndex: Int)
    case emptyTranscriptText(pieceIndex: Int)
    case invalidDiarizationRange(intervalIndex: Int)
    case invalidSpeakerLabel(intervalIndex: Int)
    case invalidConfidence(intervalIndex: Int)
    case unmatchedTranscriptPiece(pieceIndex: Int)
}

struct TimestampTranscriptAligner: TranscriptAligning {
    private static let maximumInputCount = 100_000
    private static let maximumFallbackGapMilliseconds = 500
    private static let maximumCoalescingGapMilliseconds = 1_200
    private static let patientSimilarityThreshold = 0.82
    private static let patientSimilarityMargin = 0.08

    private let idFactory: @Sendable () -> UUID

    init(idFactory: @escaping @Sendable () -> UUID = { UUID() }) {
        self.idFactory = idFactory
    }

    func align(_ input: TranscriptAlignmentInput) throws -> [TranscriptSegment] {
        let pieces = try validatedPieces(input.transcript.segments)
        let intervals = try validatedIntervals(input.diarization.intervals)
        let speakers = resolvedSpeakers(for: input, intervals: intervals)
        var matches: [MatchedPiece] = []
        matches.reserveCapacity(pieces.count)
        for piece in pieces.prefix(Self.maximumInputCount) {
            guard let match = bestMatch(for: piece, intervals: intervals) else {
                throw TranscriptAlignmentError.unmatchedTranscriptPiece(pieceIndex: piece.originalIndex)
            }
            matches.append(MatchedPiece(piece: piece, label: match.label, confidence: match.confidence))
        }
        guard matches.count == pieces.count, !matches.isEmpty else {
            throw TranscriptAlignmentError.inputLimitExceeded
        }
        _ = dominantEarlyCluster(in: intervals)
        return coalescedSegments(matches, appointmentID: input.appointmentID, speakers: speakers)
    }

    private func validatedPieces(_ source: [TranscriptPiece]) throws -> [IndexedPiece] {
        guard !source.isEmpty else { throw TranscriptAlignmentError.emptyTranscript }
        guard source.count <= Self.maximumInputCount else { throw TranscriptAlignmentError.inputLimitExceeded }
        var result: [IndexedPiece] = []
        result.reserveCapacity(source.count)
        for (index, piece) in source.enumerated().prefix(Self.maximumInputCount) {
            guard !piece.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptAlignmentError.emptyTranscriptText(pieceIndex: index)
            }
            guard let start = piece.startMilliseconds, let end = piece.endMilliseconds else {
                throw TranscriptAlignmentError.missingTimestamp(pieceIndex: index)
            }
            guard start >= 0, end > start else {
                throw TranscriptAlignmentError.invalidTranscriptRange(pieceIndex: index)
            }
            result.append(IndexedPiece(text: piece.text, start: start, end: end, originalIndex: index))
        }
        return result.sorted { ($0.start, $0.end, $0.originalIndex) < ($1.start, $1.end, $1.originalIndex) }
    }

    private func validatedIntervals(_ source: [DiarizationInterval]) throws -> [IndexedInterval] {
        guard !source.isEmpty else { throw TranscriptAlignmentError.emptyDiarization }
        guard source.count <= Self.maximumInputCount else { throw TranscriptAlignmentError.inputLimitExceeded }
        var result: [IndexedInterval] = []
        result.reserveCapacity(source.count)
        for (index, interval) in source.enumerated().prefix(Self.maximumInputCount) {
            guard !interval.rawSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptAlignmentError.invalidSpeakerLabel(intervalIndex: index)
            }
            guard interval.startMilliseconds >= 0, interval.endMilliseconds > interval.startMilliseconds else {
                throw TranscriptAlignmentError.invalidDiarizationRange(intervalIndex: index)
            }
            guard interval.confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
                throw TranscriptAlignmentError.invalidConfidence(intervalIndex: index)
            }
            result.append(IndexedInterval(value: interval, originalIndex: index))
        }
        return result.sorted { intervalOrder($0, $1) }
    }

    private func bestMatch(for piece: IndexedPiece, intervals: [IndexedInterval]) -> ClusterMatch? {
        var candidates: [String: OverlapCandidate] = [:]
        for interval in intervals.prefix(Self.maximumInputCount) {
            let overlap = max(0, min(piece.end, interval.end) - max(piece.start, interval.start))
            guard overlap > 0 else { continue }
            candidates[interval.label, default: OverlapCandidate(interval)].add(interval, overlap: overlap)
        }
        if let overlapMatch = greatestOverlap(in: candidates) { return overlapMatch }
        guard let nearest = nearestInterval(for: piece, intervals: intervals) else { return nil }
        return ClusterMatch(label: nearest.label, confidence: nearest.confidence)
    }

    private func greatestOverlap(in candidates: [String: OverlapCandidate]) -> ClusterMatch? {
        var best: OverlapCandidate?
        for candidate in candidates.values.prefix(Self.maximumInputCount) {
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.overlap > current.overlap
                || (candidate.overlap == current.overlap && intervalOrder(candidate.earliest, current.earliest)) {
                best = candidate
            }
        }
        guard let best else { return nil }
        return ClusterMatch(label: best.earliest.label, confidence: best.confidence)
    }

    private func nearestInterval(for piece: IndexedPiece, intervals: [IndexedInterval]) -> IndexedInterval? {
        var best: IndexedInterval?
        var bestGap = Int.max
        for interval in intervals.prefix(Self.maximumInputCount) {
            let gap = piece.end <= interval.start ? interval.start - piece.end : piece.start - interval.end
            guard gap >= 0 else { continue }
            if gap < bestGap || (gap == bestGap && precedes(interval, best)) {
                best = interval
                bestGap = gap
            }
        }
        return bestGap <= Self.maximumFallbackGapMilliseconds ? best : nil
    }

    private func coalescedSegments(
        _ matches: [MatchedPiece],
        appointmentID: UUID,
        speakers: [String: TranscriptSegment.Speaker]
    ) -> [TranscriptSegment] {
        var groups: [SegmentAccumulator] = []
        groups.reserveCapacity(matches.count)
        for match in matches.prefix(Self.maximumInputCount) {
            let gap = groups.last.map { match.piece.start - $0.end } ?? Int.max
            if !groups.isEmpty, groups[groups.count - 1].label == match.label,
               gap <= Self.maximumCoalescingGapMilliseconds {
                groups[groups.count - 1].append(match)
            } else {
                groups.append(SegmentAccumulator(match))
            }
        }
        return groups.prefix(Self.maximumInputCount).map { group in
            TranscriptSegment(
                id: idFactory(),
                appointmentID: appointmentID,
                speaker: speakers[group.label] ?? .unknown,
                rawSpeakerLabel: group.label,
                startMilliseconds: group.start,
                endMilliseconds: group.end,
                text: group.texts.joined(separator: " "),
                confidence: group.confidence
            )
        }
    }

    private func resolvedSpeakers(
        for input: TranscriptAlignmentInput,
        intervals: [IndexedInterval]
    ) -> [String: TranscriptSegment.Speaker] {
        let labels = Set(intervals.prefix(Self.maximumInputCount).map(\.label))
        var result: [String: TranscriptSegment.Speaker] = [:]
        let assignments = input.assignments.prefix(Self.maximumInputCount).filter {
            $0.appointmentID == input.appointmentID && labels.contains($0.rawSpeakerLabel)
        }.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt
        }
        for assignment in assignments.prefix(Self.maximumInputCount) {
            result[assignment.rawSpeakerLabel] = assignment.speaker
        }
        guard !result.values.contains(.patient),
              let inferred = inferredPatientLabel(input: input, excluding: Set(result.keys)) else { return result }
        result[inferred] = .patient
        return result
    }

    private func inferredPatientLabel(input: TranscriptAlignmentInput, excluding: Set<String>) -> String? {
        var scores: [String: Double] = [:]
        for embedding in input.diarization.speakerEmbeddings.prefix(Self.maximumInputCount) {
            guard embedding.modelID == input.diarization.modelID, !excluding.contains(embedding.rawSpeakerLabel) else { continue }
            for profile in input.patientVoiceProfiles.prefix(Self.maximumInputCount) where profile.modelID == input.diarization.modelID {
                guard let similarity = cosineSimilarity(embedding.values, profile.embedding) else { continue }
                scores[embedding.rawSpeakerLabel] = max(scores[embedding.rawSpeakerLabel] ?? -1, similarity)
            }
        }
        let ranked = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let best = ranked.first, best.value >= Self.patientSimilarityThreshold else { return nil }
        let runnerUp = ranked.dropFirst().first?.value ?? -1
        return best.value - runnerUp >= Self.patientSimilarityMargin ? best.key : nil
    }

    private func cosineSimilarity(_ left: [Float], _ right: [Float]) -> Double? {
        guard !left.isEmpty, left.count == right.count, left.count <= 4_096 else { return nil }
        var dot = 0.0
        var leftMagnitude = 0.0
        var rightMagnitude = 0.0
        for index in left.indices.prefix(4_096) {
            let lhs = Double(left[index])
            let rhs = Double(right[index])
            guard lhs.isFinite, rhs.isFinite else { return nil }
            dot += lhs * rhs
            leftMagnitude += lhs * lhs
            rightMagnitude += rhs * rhs
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return nil }
        let similarity = dot / (leftMagnitude.squareRoot() * rightMagnitude.squareRoot())
        return similarity.isFinite ? max(-1, min(1, similarity)) : nil
    }

    private func dominantEarlyCluster(in intervals: [IndexedInterval]) -> String? {
        let firstMinuteEnd = 60_000
        guard Set(intervals.prefix(Self.maximumInputCount).map(\.label)).count == 2 else { return nil }
        var durations: [String: Int] = [:]
        for interval in intervals.prefix(Self.maximumInputCount) {
            let duration = max(0, min(firstMinuteEnd, interval.end) - interval.start)
            if duration > 0 { durations[interval.label, default: 0] += duration }
        }
        return durations.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
    }

    private func precedes(_ candidate: IndexedInterval, _ current: IndexedInterval?) -> Bool {
        guard let current else { return true }
        return intervalOrder(candidate, current)
    }

    private func intervalOrder(_ left: IndexedInterval, _ right: IndexedInterval) -> Bool {
        (left.start, left.label, left.end, left.originalIndex) < (right.start, right.label, right.end, right.originalIndex)
    }
}

private struct IndexedPiece {
    let text: String
    let start: Int
    let end: Int
    let originalIndex: Int
}

private struct IndexedInterval {
    let value: DiarizationInterval
    let originalIndex: Int

    var label: String { value.rawSpeakerLabel }
    var start: Int { value.startMilliseconds }
    var end: Int { value.endMilliseconds }
    var confidence: Double? { value.confidence }
}

private struct MatchedPiece {
    let piece: IndexedPiece
    let label: String
    let confidence: Double?
}

private struct ClusterMatch {
    let label: String
    let confidence: Double?
}

private struct OverlapCandidate {
    private(set) var earliest: IndexedInterval
    private(set) var overlap = 0
    private var weightedConfidence = 0.0
    private var confidenceDuration = 0

    init(_ interval: IndexedInterval) {
        earliest = interval
    }

    mutating func add(_ interval: IndexedInterval, overlap: Int) {
        if interval.start < earliest.start
            || (interval.start == earliest.start && interval.label < earliest.label) {
            earliest = interval
        }
        self.overlap += overlap
        guard let confidence = interval.confidence else { return }
        weightedConfidence += confidence * Double(overlap)
        confidenceDuration += overlap
    }

    var confidence: Double? {
        confidenceDuration > 0 ? weightedConfidence / Double(confidenceDuration) : nil
    }
}

private struct SegmentAccumulator {
    let label: String
    private(set) var start: Int
    private(set) var end: Int
    private(set) var texts: [String]
    private var weightedConfidence = 0.0
    private var confidenceDuration = 0

    init(_ match: MatchedPiece) {
        label = match.label
        start = match.piece.start
        end = match.piece.end
        texts = [match.piece.text]
        addConfidence(from: match)
    }

    mutating func append(_ match: MatchedPiece) {
        start = min(start, match.piece.start)
        end = max(end, match.piece.end)
        texts.append(match.piece.text)
        addConfidence(from: match)
    }

    var confidence: Double? {
        confidenceDuration > 0 ? weightedConfidence / Double(confidenceDuration) : nil
    }

    private mutating func addConfidence(from match: MatchedPiece) {
        guard let value = match.confidence else { return }
        let duration = match.piece.end - match.piece.start
        weightedConfidence += value * Double(duration)
        confidenceDuration += duration
    }
}
