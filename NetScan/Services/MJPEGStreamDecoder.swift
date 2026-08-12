import Foundation
import UIKit

/// Connects to an MJPEG-over-HTTP stream (`multipart/x-mixed-replace`) and
/// decodes it frame by frame — the same content a browser renders when you
/// open a camera's "video.mjpg"-style URL directly. No video codec, no RTSP:
/// just JPEG frames separated by a boundary marker taken from the response's
/// Content-Type header.
final class MJPEGStreamDecoder: NSObject, URLSessionDataDelegate {
    var onFrame: ((UIImage) -> Void)?
    var onConnected: (() -> Void)?
    var onError: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var boundaryMarker: Data?

    func start(url: URL, username: String?, password: String?) {
        stop()
        buffer.removeAll()
        boundaryMarker = nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        var request = URLRequest(url: url)
        if let username, let password, !username.isEmpty {
            let raw = "\(username):\(password)"
            if let base64 = raw.data(using: .utf8)?.base64EncodedString() {
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }

        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           let range = contentType.range(of: "boundary=") {
            let rawBoundary = String(contentType[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            boundaryMarker = ("--" + rawBoundary).data(using: .utf8)
            onConnected?()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        extractFrames()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onError?(error.localizedDescription)
        }
    }

    private func extractFrames() {
        guard let boundary = boundaryMarker else { return }
        while let boundaryRange = buffer.range(of: boundary) {
            let part = buffer.subdata(in: buffer.startIndex..<boundaryRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<boundaryRange.upperBound)

            guard let headerEnd = part.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let imageData = part.subdata(in: headerEnd.upperBound..<part.endIndex)
            if let image = UIImage(data: imageData) {
                onFrame?(image)
            }
        }
    }
}
