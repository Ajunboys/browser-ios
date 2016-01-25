/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
#if !NO_FABRIC
import Fabric
import Crashlytics
#endif

private let _singleton = BraveApp()

let kAppBootingIncompleteFlag = "kAppBootingIncompleteFlag"
let kDesktopUserAgent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_8; it-it) AppleWebKit/533.16 (KHTML, like Gecko) Version/5.0 Safari/533.16"

#if !TEST
    func getApp() -> AppDelegate {
        return UIApplication.sharedApplication().delegate as! AppDelegate
    }
#endif

// Any app-level hooks we need from Firefox, just add a call to here
class BraveApp {
    static var isSafeToRestoreTabs = true
    // If app runs for this long, clear the saved pref that indicates it is safe to restore tabs
    static let kDelayBeforeDecidingAppHasBootedOk = (Int64(NSEC_PER_SEC) * 10) // 10 sec

    class var singleton: BraveApp {
        return _singleton
    }

#if !TEST
    class func getCurrentWebView() -> BraveWebView? {
        return getApp().browserViewController.tabManager.selectedTab?.webView
    }
#endif

    private init() {
    }

    class func isIPhoneLandscape() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func isIPhonePortrait() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func setupCacheDefaults() {
        NSURLCache.sharedURLCache().memoryCapacity = 6 * 1024 * 1024; // 6 MB
        NSURLCache.sharedURLCache().diskCapacity = 40 * 1024 * 1024;
    }

    // Be aware: the Prefs object has not been created yet
    class func willFinishLaunching_begin() {
#if !NO_FABRIC
        Fabric.with([Crashlytics.self])
#endif
        BraveApp.setupCacheDefaults()
        NSURLProtocol.registerClass(URLProtocol);

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "didEnterBackground:", name: UIApplicationDidEnterBackgroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "willEnterForeground:", name: UIApplicationWillEnterForegroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "memoryWarning:", name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)

        #if !TEST
        //  these quiet the logging from the core of fx ios
        GCDWebServer.setLogLevel(5)
        Logger.syncLogger.setup(.None)
        Logger.browserLogger.setup(.None)
        #endif

        #if DEBUG
            NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
                selector: "prefsChanged_verifySuiteNameIsOk:", name: NSUserDefaultsDidChangeNotification, object: nil)
            #if !TEST
                if BraveUX.DebugShowBorders {
                    UIView.bordersOn()
                }
            #endif
            // desktop UA for testing
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      let desktop = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_8; it-it) AppleWebKit/533.16 (KHTML, like Gecko) Version/5.0 Safari/533.16"
            //      defaults.registerDefaults(["UserAgent": desktop])

        #endif
    }

    // Prefs are created at this point
    class func willFinishLaunching_end() {
        if AppConstants.IsRunningTest {
            print("In test mode, bypass automatic vault registration.")
        } else {
            VaultManager.userProfileInit()
        }

        BraveApp.isSafeToRestoreTabs = BraveApp.getPref(kAppBootingIncompleteFlag) == nil
        BraveApp.setPref("remove me when booted", forKey: kAppBootingIncompleteFlag)
        BraveApp.getPrefs()?.synchronize()
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, BraveApp.kDelayBeforeDecidingAppHasBootedOk),
            dispatch_get_main_queue(), {
                BraveApp.removePref(kAppBootingIncompleteFlag)
        })
        #if !TEST
            BraveScrollController.hideShowToolbarEnabled = BraveApp.getPref(BraveUX.PrefKeyIsToolbarHidingEnabled) as? Bool ?? true

        #endif
        AdBlocker.singleton.networkFileLoader.loadData()
        TrackingProtection.singleton.networkFileLoader.loadData()
        HttpsEverywhere.singleton.loadData()
    }

    // This can only be checked ONCE, the flag is cleared after this.
    // This is because BrowserViewController asks this question after the startup phase,
    // when tabs are being created by user actions. So without more refactoring of the
    // Firefox logic, this is the simplest solution.
    class func shouldRestoreTabs() -> Bool {
        let ok = BraveApp.isSafeToRestoreTabs
        BraveApp.isSafeToRestoreTabs = true
        return ok
    }

    @objc func memoryWarning(_: NSNotification) {
        NSURLCache.sharedURLCache().memoryCapacity = 0
        BraveApp.setupCacheDefaults()
    }

    @objc func didEnterBackground(_: NSNotification) {
    }

    @objc func willEnterForeground(_ : NSNotification) {
    }

    class func shouldHandleOpenURL(components: NSURLComponents) -> Bool {
        // TODO look at what x-callback is for
        return components.scheme == "brave" || components.scheme == "brave-x-callback"
    }

    class func getPrefs() -> NSUserDefaults? {
        #if !TEST
            assert(NSUserDefaultsPrefs.prefixWithDotForBrave.characters.count > 0)
        #endif
        return NSUserDefaults(suiteName: "group.com.brave.ios.browser")
    }

    class func getPref(var pref: String) -> AnyObject? {
        #if !TEST
            pref = NSUserDefaultsPrefs.prefixWithDotForBrave + pref
        #endif

        return getPrefs()?.objectForKey(pref)
    }

    class func setPref(val: AnyObject, var forKey: String) {
        #if !TEST
            forKey = NSUserDefaultsPrefs.prefixWithDotForBrave + forKey
        #endif
        getPrefs()?.setObject(val, forKey: forKey)
    }

    class func removePref(var pref: String) {
        #if !TEST
            pref = NSUserDefaultsPrefs.prefixWithDotForBrave + pref
        #endif
        getPrefs()?.removeObjectForKey(pref)
    }

    #if DEBUG
    // do a debug only verification that using the correct name for getting the defaults
    @objc func prefsChanged_verifySuiteNameIsOk(info: NSNotification) {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSUserDefaultsDidChangeNotification, object: nil)
        let defaults = info.object as! NSUserDefaults
        let defaults2 = NSUserDefaults(suiteName: "group.com.brave.ios.browser")
        assert(defaults.dictionaryRepresentation().elementsEqual(defaults2!.dictionaryRepresentation(), isEquivalent: { (a:(String, AnyObject), b:(String, AnyObject)) -> Bool in
            return a.1 as? String == b.1 as? String
        }))
    }
    #endif

    static func showErrorAlert(title title: String,  error: String) {
        UIAlertView(title: title, message: error, delegate: nil, cancelButtonTitle: "Close").show()
    }

    static func statusBarHeight() -> CGFloat {
        if UIScreen.mainScreen().traitCollection.verticalSizeClass == .Compact {
            return 0
        }
        return 20
    }
}
