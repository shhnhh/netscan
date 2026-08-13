import Foundation

/// Sends UPnP AVTransport/RenderingControl SOAP commands (play/pause/stop,
/// volume) to a device SSDP already found — smart speakers, TVs, AVRs.
/// This is the same mechanism DLNA controller apps use: fetch the device's
/// description XML (the SSDP LOCATION URL), find the AVTransport/
/// RenderingControl service's controlURL, and POST a small SOAP envelope to
/// it. No pairing or account needed — the same "anyone on the LAN can send
/// a play/pause" trust model UPnP has always used.
enum UPnPMediaController {
    struct ControlPoints {
        let avTransport: URL?
        let renderingControl: URL?

        var hasAnyControl: Bool { avTransport != nil || renderingControl != nil }
    }

    /// Fetches the device description XML and locates both control services
    /// it might expose. Either (or both) can come back nil — plenty of UPnP
    /// devices (routers, NAS boxes) advertise themselves via SSDP without
    /// being media renderers at all.
    static func discoverControlPoints(location: String) async -> ControlPoints {
        guard let url = URL(string: location) else {
            return ControlPoints(avTransport: nil, renderingControl: nil)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else {
            return ControlPoints(avTransport: nil, renderingControl: nil)
        }

        let avPath = extractControlURL(xml: xml, serviceType: "AVTransport")
        let rcPath = extractControlURL(xml: xml, serviceType: "RenderingControl")
        return ControlPoints(
            avTransport: avPath.flatMap { resolveURL(controlURL: $0, location: location) },
            renderingControl: rcPath.flatMap { resolveURL(controlURL: $0, location: location) }
        )
    }

    /// UPnP device descriptions list each service as a `<service>` block
    /// containing its `<serviceType>` and `<controlURL>` — a simple
    /// substring match per block is enough since the schema always uses
    /// these exact tag names, same approach as SSDPScanner's friendlyName
    /// extraction.
    static func extractControlURL(xml: String, serviceType: String) -> String? {
        let blocks = xml.components(separatedBy: "<service>")
        for block in blocks.dropFirst() {
            guard let end = block.range(of: "</service>") else { continue }
            let serviceBlock = block[block.startIndex..<end.lowerBound]
            guard serviceBlock.contains(serviceType) else { continue }
            guard let start = serviceBlock.range(of: "<controlURL>"),
                  let stop = serviceBlock.range(of: "</controlURL>") else { continue }
            return String(serviceBlock[start.upperBound..<stop.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// `controlURL` is usually relative ("/upnp/control/AVTransport1") —
    /// resolve it against the device description's own URL, which is what
    /// UPnP devices expect callers to do absent an explicit `<URLBase>`.
    static func resolveURL(controlURL: String, location: String) -> URL? {
        guard let base = URL(string: location) else { return nil }
        return URL(string: controlURL, relativeTo: base)?.absoluteURL
    }

    enum TransportAction: String {
        case play = "Play"
        case pause = "Pause"
        case stop = "Stop"
    }

    @discardableResult
    static func play(controlURL: URL) async -> Bool {
        await sendTransportAction(.play, controlURL: controlURL)
    }

    @discardableResult
    static func pause(controlURL: URL) async -> Bool {
        await sendTransportAction(.pause, controlURL: controlURL)
    }

    @discardableResult
    static func stop(controlURL: URL) async -> Bool {
        await sendTransportAction(.stop, controlURL: controlURL)
    }

    @discardableResult
    static func setVolume(_ volume: Int, controlURL: URL) async -> Bool {
        let clamped = max(0, min(100, volume))
        let body = soapEnvelope(
            action: "SetVolume",
            serviceType: avTransportRenderingType,
            arguments: "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\(clamped)</DesiredVolume>"
        )
        return await post(body: body, controlURL: controlURL, serviceType: avTransportRenderingType, action: "SetVolume")
    }

    private static let avTransportType = "urn:schemas-upnp-org:service:AVTransport:1"
    private static let avTransportRenderingType = "urn:schemas-upnp-org:service:RenderingControl:1"

    private static func sendTransportAction(_ action: TransportAction, controlURL: URL) async -> Bool {
        let extraArgs = action == .play ? "<Speed>1</Speed>" : ""
        let body = soapEnvelope(
            action: action.rawValue,
            serviceType: avTransportType,
            arguments: "<InstanceID>0</InstanceID>" + extraArgs
        )
        return await post(body: body, controlURL: controlURL, serviceType: avTransportType, action: action.rawValue)
    }

    static func soapEnvelope(action: String, serviceType: String, arguments: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(serviceType)">
        \(arguments)
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """
    }

    private static func post(body: String, controlURL: URL, serviceType: String, action: String) async -> Bool {
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.timeoutInterval = 4

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
