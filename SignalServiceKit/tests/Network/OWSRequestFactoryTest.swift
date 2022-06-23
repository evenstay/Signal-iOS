//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSRequestFactoryTest: XCTestCase {
    func testBoostCreatePaymentIntentWithAmount() {
        let request = OWSRequestFactory.boostCreatePaymentIntent(withAmount: 123, inCurrencyCode: "CHF", level: 456)

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/create")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(Set(request.parameters.keys), Set(["currency", "amount", "level"]))
        XCTAssertEqual(request.parameters["currency"] as? String, "chf")
        XCTAssertEqual(request.parameters["amount"] as? UInt, 123)
        XCTAssertEqual(request.parameters["level"] as? UInt64, 456)
        XCTAssertFalse(request.shouldHaveAuthorizationHeaders)
    }

    func testGiftBadgePricesRequest() throws {
        let request = OWSRequestFactory.giftBadgePricesRequest()

        XCTAssertEqual(request.url?.path, "v1/subscription/boost/amounts/gift")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.parameters.isEmpty)
    }
}
