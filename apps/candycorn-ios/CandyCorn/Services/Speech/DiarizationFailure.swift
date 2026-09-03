import AVFoundation
import FluidAudio
import Foundation

enum DiarizationFailure: Error, Equatable, Sendable {
    case modelDownloadOffline
    case modelInstallationFailed
    case invalidAudio
    case emptyResult
    case processingFailed

    static func modelPreparation(_ error: any Error) -> DiarizationFailure {
        if containsOfflineNetworkError(error, depth: 0) {
            return .modelDownloadOffline
        }
        return .modelInstallationFailed
    }

    static func processing(_ error: any Error) -> DiarizationFailure {
        if let offlineError = error as? OfflineDiarizationError {
            if case .noSpeechDetected = offlineError {
                return .emptyResult
            }
        }
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain || isFileReadError(nsError) {
            return .invalidAudio
        }
        return .processingFailed
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func containsOfflineNetworkError(_ error: any Error, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return true
        }
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .networkDisabled, .modelMissing:
                return true
            case let .downloadFailed(_, underlying):
                return containsOfflineNetworkError(underlying, depth: depth + 1)
            default:
                return false
            }
        }
        let nsError = error as NSError
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error else {
            return false
        }
        return containsOfflineNetworkError(underlying, depth: depth + 1)
    }

    private static func isFileReadError(_ error: NSError) -> Bool {
        guard error.domain == NSCocoaErrorDomain else { return false }
        return error.code == NSFileNoSuchFileError
            || error.code == NSFileReadNoPermissionError
            || error.code == NSFileReadCorruptFileError
            || error.code == NSFileReadUnknownError
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
    ]
}
