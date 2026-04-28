import Foundation

/// Captures the requests sent through a `URLSession` configured with this
/// protocol class, and returns canned `(HTTPURLResponse, Data)` pairs.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _capturedRequests: [URLRequest] = []

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _capturedRequests = []
    }

    static var capturedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _capturedRequests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _capturedRequests = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler: Handler? = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        // Capture the request — including its body, which URLProtocol
        // strips out by default unless we read `httpBodyStream`.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            captured.httpBody = Data(reading: stream)
        }
        Self.lock.lock()
        Self._capturedRequests.append(captured)
        Self.lock.unlock()

        do {
            let (response, data) = try handler(captured)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()
        defer { input.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            self.append(buffer, count: read)
        }
    }
}
