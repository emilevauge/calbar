import Foundation
import Network
import CalbarCore

/// HTTP server on 127.0.0.1 that catches Google's OAuth redirect. Google
/// allows any port on the loopback address for Desktop clients. Only a
/// request carrying the expected `state` is delivered; anything else gets
/// a 404 and the server keeps listening.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let expectedState: String
    private let queue = DispatchQueue(label: "dev.calbar.loopback")
    // Only touched on `queue`.
    private var continuation: CheckedContinuation<URLComponents, Error>?
    private var pending: Result<URLComponents, Error>?
    private var startResumed = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    private static let grantedPage = page("Calbar is connected.", "You can close this tab.")
    private static let refusedPage = page("Sign-in refused.", "You can close this tab.")

    private static func page(_ title: String, _ message: String) -> String {
        """
        <!doctype html><meta charset="utf-8"><title>Calbar</title>
        <body style="font: 15px -apple-system; text-align: center; margin-top: 20vh">
        <h2>\(title)</h2><p>\(message)</p></body>
        """
    }

    init(expectedState: String) throws {
        self.expectedState = expectedState
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    /// Starts listening and returns the port picked by the system.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready where !self.startResumed:
                    self.startResumed = true
                    cont.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed(let error):
                    self.finish(start: cont, error: error)
                case .cancelled:
                    self.finish(start: cont, error: CancellationError())
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Query of the redirect. Throws `CancellationError` after `cancel()`.
    func waitForCallback() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let pending = self.pending {
                    self.pending = nil
                    cont.resume(with: pending)
                } else {
                    self.continuation = cont
                }
            }
        }
    }

    /// Makes `waitForCallback` throw `CancellationError` and stops listening.
    func cancel() {
        queue.async {
            self.deliver(.failure(CancellationError()))
            self.shutDown()
        }
    }

    func stop() {
        queue.async { self.shutDown() }
    }

    /// Runs on `queue`. The listener stopped: fail whichever wait is pending.
    private func finish(start cont: CheckedContinuation<UInt16, Error>, error: Error) {
        if startResumed {
            deliver(.failure(error))
        } else {
            startResumed = true
            cont.resume(throwing: error)
        }
    }

    /// Runs on `queue`.
    private func shutDown() {
        listener.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    /// Runs on `queue`.
    private func handle(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.connections[id] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            // Request line: "GET /?code=...&state=... HTTP/1.1"
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            guard let components = URLComponents(string: "http://127.0.0.1" + target),
                  components.path == "/" else {
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            switch GoogleOAuth.classifyCallback(components, expectedState: self.expectedState) {
            case .unrelated:
                self.respond(connection, status: "404 Not Found", body: "")
            case .granted:
                self.respond(connection, status: "200 OK", body: Self.grantedPage)
                self.deliver(.success(components))
            case .refused:
                self.respond(connection, status: "200 OK", body: Self.refusedPage)
                self.deliver(.success(components))
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Runs on `queue`. Keeps the first result only.
    private func deliver(_ result: Result<URLComponents, Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else if pending == nil {
            pending = result
        }
    }
}
