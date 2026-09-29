import Foundation
import MacalCore

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
        case .http(let status, _):
            return "Google Calendar API error (\(status))."
        case .invalidResponse:
            return "Invalid response from Google."
        }
    default:
        return "Google sign-in failed."
    }
}
