import Foundation
import Network

struct CommandInfo: Decodable {
    let command: String
    let explanation: String
    let warning: String?
}

protocol CommandServerDelegate: AnyObject {
    func serverDidReceiveCommand(_ info: CommandInfo)
}

class CommandServer {
    static let defaultPort: UInt16 = 19876

    private let port: UInt16
    private var listener: NWListener?
    weak var delegate: CommandServerDelegate?

    init(port: UInt16 = CommandServer.defaultPort) {
        self.port = port
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            debugLog("Invalid port: \(port)")
            return
        }

        do {
            listener = try NWListener(using: .tcp, on: nwPort)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    debugLog("Listening on port \(self.port)")
                case .failed(let error):
                    debugLog("Server failed: \(error)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            debugLog("Failed to start listener: \(error)")
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ClaudeCommandHelper] \(message)")
        #endif
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTPRequest(connection: connection, buffer: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buffer = buffer

            if let data = data {
                buffer.append(data)
            }

            guard let requestString = String(data: buffer, encoding: .utf8) else {
                connection.cancel()
                return
            }

            guard let headerEnd = requestString.range(of: "\r\n\r\n") else {
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self?.receiveHTTPRequest(connection: connection, buffer: buffer)
                }
                return
            }

            let headers = String(requestString[..<headerEnd.lowerBound])
            let body = String(requestString[headerEnd.upperBound...])
            let contentLength = Self.parseContentLength(from: headers)

            if body.utf8.count >= contentLength {
                self?.processRequest(body: body, connection: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self?.receiveHTTPRequest(connection: connection, buffer: buffer)
            }
        }
    }

    private static func parseContentLength(from headers: String) -> Int {
        for line in headers.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    // MARK: - Request processing

    private func processRequest(body: String, connection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let info = try? JSONDecoder().decode(CommandInfo.self, from: jsonData) else {
            sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"invalid request\"}")
            return
        }

        sendResponse(connection: connection, statusCode: 200, body: "{\"status\":\"received\"}")

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.serverDidReceiveCommand(info)
        }
    }

    // MARK: - HTTP response

    private static let httpStatusTexts: [Int: String] = [200: "OK", 400: "Bad Request"]

    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText = Self.httpStatusTexts[statusCode, default: "Unknown"]
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
