import Darwin
import Foundation

/// Rough ping/download/upload throughput test against Cloudflare's public,
/// unauthenticated speed-test endpoints (the same ones speed.cloudflare.com
/// itself uses) — no API key, no server of our own to run and pay for.
final class SpeedTestService: NSObject {
    private var session: URLSession!

    private var downloadStart: Date?
    private var downloadBytes = 0
    private var downloadDeadline: Date?
    private var downloadCompletion: ((Double?) -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func measurePing(samples: Int = 3) async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        var durationsMs: [Double] = []
        for _ in 0..<samples {
            let start = Date()
            guard (try? await URLSession.shared.data(for: request)) != nil else { continue }
            durationsMs.append(Date().timeIntervalSince(start) * 1000)
        }
        guard !durationsMs.isEmpty else { return nil }
        return durationsMs.sorted()[durationsMs.count / 2]
    }

    func measureDownload(durationLimit: TimeInterval = 6) async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=50000000") else { return nil }
        downloadBytes = 0
        downloadStart = Date()
        downloadDeadline = Date().addingTimeInterval(durationLimit)

        return await withCheckedContinuation { continuation in
            downloadCompletion = { mbps in continuation.resume(returning: mbps) }
            let task = session.dataTask(with: url)
            task.resume()

            DispatchQueue.global().asyncAfter(deadline: .now() + durationLimit) { [weak self] in
                task.cancel()
                self?.finishDownload()
            }
        }
    }

    func measureUpload(bytes: Int = 8_000_000, durationLimit: TimeInterval = 6) async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = durationLimit

        var payload = Data(count: bytes)
        payload.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                arc4random_buf(base, buffer.count)
            }
        }

        let start = Date()
        return await withCheckedContinuation { continuation in
            let task = session.uploadTask(with: request, from: payload) { _, _, error in
                let elapsed = Date().timeIntervalSince(start)
                guard error == nil, elapsed > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (Double(bytes) * 8 / 1_000_000) / elapsed)
            }
            task.resume()
        }
    }

    private func finishDownload() {
        guard let completion = downloadCompletion else { return }
        downloadCompletion = nil
        guard let start = downloadStart, downloadBytes > 0 else {
            completion(nil)
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else {
            completion(nil)
            return
        }
        completion((Double(downloadBytes) * 8 / 1_000_000) / elapsed)
    }
}

extension SpeedTestService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        downloadBytes += data.count
        if let deadline = downloadDeadline, Date() >= deadline {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task is URLSessionDataTask {
            finishDownload()
        }
    }
}
