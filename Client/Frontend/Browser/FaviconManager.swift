/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import WebImage


class FaviconManager : BrowserHelper {
    let profile: Profile!
    weak var browser: Browser?

    init(browser: Browser, profile: Profile) {
        self.profile = profile
        self.browser = browser

        if let path = NSBundle.mainBundle().pathForResource("Favicons", ofType: "js") {
            if let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) as String {
                let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.AtDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    class func name() -> String {
        return "FaviconsManager"
    }

    func scriptMessageHandlerName() -> String? {
        return "faviconsMessageHandler"
    }

    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        let manager = SDWebImageManager.sharedManager()
        guard let tab = browser else { return }
        tab.favicons.removeAll(keepCapacity: false)

        // Result is in the form {'documentLocation' : document.location.href, 'http://icon url 1': "<type>", 'http://icon url 2': "<type" }
        guard let icons = message.body as? [String: String], documentLocation = icons["documentLocation"] else { return }
        guard let currentUrl = NSURL(string: documentLocation) else { return }

        if documentLocation.contains(WebServer.sharedInstance.base) {
            return
        }

        let site = Site(url: documentLocation, title: "")
        var favicons = [Favicon]()
        for item in icons {
            if item.0 == "documentLocation" {
                continue
            }

            if let type = Int(item.1), _ = NSURL(string: item.0), iconType = IconType(rawValue: type) {
                let favicon = Favicon(url: item.0, date: NSDate(), type: iconType, belongsTo: currentUrl)
                favicons.append(favicon)
            }
        }


        let options = tab.isPrivate ? [SDWebImageOptions.LowPriority, SDWebImageOptions.CacheMemoryOnly] : [SDWebImageOptions.LowPriority]

        func downloadIcon(icon: Favicon) {
            if let iconUrl = NSURL(string: icon.url) {
                manager.downloadImageWithURL(iconUrl, options: SDWebImageOptions(options), progress: nil, completed: { (img, err, cacheType, success, url) -> Void in
                    let fav = Favicon(url: url.absoluteString, date: NSDate(), type: icon.type, belongsTo: currentUrl)

                    if let img = img {
                        fav.width = Int(img.size.width)
                        fav.height = Int(img.size.height)
                    } else {
                        if favicons.count == 1 && favicons[0].type == .Guess {
                            // No favicon is indicated in the HTML
                            ///self.noFaviconAvailable(tab, atURL: tabUrl)
                        }
                        downloadBestIcon()
                        return
                    }

                    if !tab.isPrivate {
                        self.profile.favicons.addFavicon(fav, forSite: site)
                        if tab.favicons.isEmpty {
                            self.makeFaviconAvailable(tab, atURL: currentUrl, favicon: fav, withImage: img)
                        }
                    }
                    tab.favicons.append(fav)
                })
            }
        }

        func downloadBestIcon() {
            guard let best = getBestFavicon(favicons) else { return }
            favicons = favicons.filter { $0 != best }
            downloadIcon(best)
        }
        
        downloadBestIcon()
    }

    func makeFaviconAvailable(tab: Browser, atURL url: NSURL, favicon: Favicon, withImage image: UIImage) {
        let helper = tab.getHelper(name: "SpotlightHelper") as? SpotlightHelper
        helper?.updateImage(image, forURL: url)
    }

    func noFaviconAvailable(tab: Browser, atURL url: NSURL) {
        let helper = tab.getHelper(name: "SpotlightHelper") as? SpotlightHelper
        helper?.updateImage(forURL: url)

    }
}
