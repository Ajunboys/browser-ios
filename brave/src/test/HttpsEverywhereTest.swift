/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
#if TEST
import Foundation
import XCTest
@testable import Client
import Shared

// This fails due to the swift compiler: false casting of AnyObjects to XCUIElement, then the objects won't cast to their proper types

class HttpsEverywhereTest: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func test() {
        expectationForNotification(HttpsEverywhere.kNotificationDataLoaded, object: nil, handler:nil)
        HttpsEverywhere.singleton.networkFileLoader.loadData()
        var isOk = true
        waitForExpectationsWithTimeout(5) { (error:NSError?) -> Void in
            if let _ = error {
                isOk = false
                XCTAssert(false, "load data failed")
            }
        }

        if !isOk {
            return
        }

        let urls = ["motherboard.vice.com", "thestar.com", "www.thestar.com", "apple.com", "xkcd.com"]

        for url in urls {
            let redirected = HttpsEverywhere.singleton.tryRedirectingUrl(NSURL(string: "http://" + url)!)
            XCTAssert(redirected != nil && redirected!.scheme.startsWith("https"), "failed:" + url)
        }
    }
}
#endif