import Foundation
import CalbarCore

/// Short message for the UI. Raw details only go to NSLog.
func describe(_ error: Error) -> String {
    switch error {
    case is CancellationError:
        return "Sign-in cancelled."
    case let error as OAuthError:
        switch error {
        case .invalidGrant:
            return "Google authorization expired, reconnect the account."
        case .denied:
            return "Access denied in the browser."
        case .stateMismatch, .missingCode:
            return "Invalid response from Google, try again."
        case .missingRefreshToken:
            return "Google did not return a refresh token, try again."
        case .missingEmail:
            return "Google did not return the account email."
        case .server(let status, _):
            return "Google server error (\(status))."
        }
    case let error as URLError:
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "No Internet connection."
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Google is not responding, try again later."
        case .cancelled:
            return "Sign-in cancelled."
        default:
            return "Network error (\(error.code.rawValue))."
        }
    case let error as Keychain.Failure:
        return "Could not access the Keychain (\(error.status))."
    case let error as APIError:
        switch error {
        case .unauthorized:
            return "Google authorization refused."
        case .insufficientScope:
            return "Reconnect the account to reply."
        case .http(let status, _):
            return "Google Calendar API error (\(status))."
        case .invalidResponse:
            return "Invalid response from Google."
        }
    default:
        return "Google sign-in failed."
    }
}

/// Short message shown under the RSVP control when an answer fails.
func describeReply(_ error: Error) -> String {
    switch error {
    case RSVPPatch.Failure.notInvited:
        return "You are not a guest of this event."
    case APIError.http(403, _):
        return "Google refused the answer (403)."
    case APIError.http(404, _), APIError.http(410, _):
        return "This event no longer exists."
    case is URLError, is APIError, OAuthError.invalidGrant:
        return describe(error)
    default:
        return "Could not send the answer."
    }
}

/// Message in the new event form when creating fails.
func describeCreate(_ error: Error) -> String {
    switch error {
    case APIError.insufficientScope:
        return "Reconnect this account in Settings to create events."
    case APIError.http(403, _):
        return "Google refused to add the event (403)."
    case APIError.http(404, _):
        return "This calendar no longer exists."
    case is URLError, is APIError, OAuthError.invalidGrant:
        return describe(error)
    default:
        return "Could not create the event."
    }
}

/// Message in the editor when the Zoom meeting cannot be made.
func describeZoom(_ error: Error) -> String {
    switch error {
    case ZoomAuth.Failure.notConnected:
        return "Connect Zoom in Settings to add a Zoom meeting."
    case APIError.http(let status, _):
        return "Zoom refused to create the meeting (\(status))."
    case is URLError:
        return describe(error)
    default:
        return "Could not create the Zoom meeting."
    }
}
