import XCTest
import UIKit
@testable import BitChord

final class EngineTests: XCTestCase {
    @MainActor
    func testBundledEngineStartsOnItsActualCustomOrigin() async throws {
        struct Ping: Decodable { let `protocol`: Int }
        let delegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
        let result: Ping = try await delegate.model.service.request("ping")
        XCTAssertEqual(result.protocol, 1)
    }

    func testUpstreamTrackAndShelfItemsDecodeToTheSameNativeType() throws {
        let track = Data(#"{"videoId":"abc","title":"Track","artists":[{"name":"Artist","id":null}],"durationSec":182,"thumbnail":null}"#.utf8)
        let item = try JSONDecoder().decode(MusicItem.self, from: track)
        XCTAssertEqual(item.id, "abc"); XCTAssertEqual(item.artist, "Artist"); XCTAssertTrue(item.playable)
        let saved = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(MusicItem.self, from: saved), item)
    }
}
