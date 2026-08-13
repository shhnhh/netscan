import XCTest
@testable import NetScan

final class UPnPMediaControllerTests: XCTestCase {
    private let sampleDescription = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <device>
        <friendlyName>Living Room Speaker</friendlyName>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
            <controlURL>/upnp/control/AVTransport1</controlURL>
            <eventSubURL>/upnp/event/AVTransport1</eventSubURL>
            <SCPDURL>/AVTransport1.xml</SCPDURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
            <controlURL>/upnp/control/RenderingControl1</controlURL>
            <eventSubURL>/upnp/event/RenderingControl1</eventSubURL>
            <SCPDURL>/RenderingControl1.xml</SCPDURL>
          </service>
        </serviceList>
      </device>
    </root>
    """

    func testExtractsAVTransportControlURL() {
        let path = UPnPMediaController.extractControlURL(xml: sampleDescription, serviceType: "AVTransport")
        XCTAssertEqual(path, "/upnp/control/AVTransport1")
    }

    func testExtractsRenderingControlControlURL() {
        let path = UPnPMediaController.extractControlURL(xml: sampleDescription, serviceType: "RenderingControl")
        XCTAssertEqual(path, "/upnp/control/RenderingControl1")
    }

    func testExtractControlURLReturnsNilForMissingService() {
        XCTAssertNil(UPnPMediaController.extractControlURL(xml: sampleDescription, serviceType: "ContentDirectory"))
    }

    func testResolveURLAgainstLocation() {
        let resolved = UPnPMediaController.resolveURL(
            controlURL: "/upnp/control/AVTransport1",
            location: "http://192.168.1.50:1400/description.xml"
        )
        XCTAssertEqual(resolved?.absoluteString, "http://192.168.1.50:1400/upnp/control/AVTransport1")
    }

    func testResolveURLWithAbsoluteControlURL() {
        let resolved = UPnPMediaController.resolveURL(
            controlURL: "http://192.168.1.50:1400/other/path",
            location: "http://192.168.1.50:1400/description.xml"
        )
        XCTAssertEqual(resolved?.absoluteString, "http://192.168.1.50:1400/other/path")
    }

    func testSOAPEnvelopeContainsActionAndArguments() {
        let envelope = UPnPMediaController.soapEnvelope(
            action: "Play",
            serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
            arguments: "<InstanceID>0</InstanceID><Speed>1</Speed>"
        )
        XCTAssertTrue(envelope.contains("<u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(envelope.contains("<InstanceID>0</InstanceID>"))
        XCTAssertTrue(envelope.contains("</u:Play>"))
    }
}
