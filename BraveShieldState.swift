import Foundation
import Deferred
import Shared
import Storage

/**
 * The sqlite-backed implementation of the history protocol.
 */
public class BraveShieldStateDb {
    let db: BrowserDB
    let favicons: FaviconsTable<Favicon>
    let prefs: Prefs

    required public init?(db: BrowserDB, prefs: Prefs) {
        self.db = db
        self.favicons = FaviconsTable<Favicon>()
        self.prefs = prefs

        // BrowserTable exists only to perform create/update etc. operations -- it's not
        // a queryable thing that needs to stick around.
        if !db.createOrUpdate(BrowserTable()) {
            return nil
        }
    }
}


// This is our default favicons store.
class BraveShieldTable: GenericTable<BraveShieldTableRow> {
    override var name: String { return TableFavicons }
    override var rows: String { return "" }
    override func create(db: SQLiteDBConnection) -> Bool {
        // Nothing to do: BrowserTable does it all.
        return true
    }

    override func getInsertAndArgs(inout item: Favicon) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        args.append(item.url)
        args.append(item.width)
        args.append(item.height)
        args.append(item.date)
        args.append(item.type.rawValue)
        return ("INSERT INTO \(TableFavicons) (url, width, height, date, type) VALUES (?,?,?,?,?)", args)
    }

    override func getUpdateAndArgs(inout item: Favicon) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        args.append(item.width)
        args.append(item.height)
        args.append(item.date)
        args.append(item.type.rawValue)
        args.append(item.url)
        return ("UPDATE \(TableFavicons) SET width = ?, height = ?, date = ?, type = ? WHERE url = ?", args)
    }

    override func getDeleteAndArgs(inout item: Favicon?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let icon = item {
            args.append(icon.url)
            return ("DELETE FROM \(TableFavicons) WHERE url = ?", args)
        }

        // TODO: don't delete icons that are in use. Bug 1161630.
        return ("DELETE FROM \(TableFavicons)", args)
    }

    override var factory: ((row: SDRow) -> Favicon)? {
        return { row -> Favicon in
            let icon = Favicon(url: row["url"] as! String, date: NSDate(timeIntervalSince1970: row["date"] as! Double), type: IconType(rawValue: row["type"] as! Int)!)
            icon.id = row["id"] as? Int
            return icon
        }
    }

    override func getQueryAndArgs(options: QueryOptions?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let filter: AnyObject = options?.filter {
            args.append("%\(filter)%")
            return ("SELECT id, url, date, type FROM \(TableFavicons) WHERE url LIKE ?", args)
        }
        return ("SELECT id, url, date, type FROM \(TableFavicons)", args)
    }

    func getIDFor(db: SQLiteDBConnection, obj: Favicon) -> Int? {
        let opts = QueryOptions()
        opts.filter = obj.url

        let cursor = query(db, options: opts)
        if (cursor.count != 1) {
            return nil
        }
        return cursor[0]?.id
    }

    func insertOrUpdate(db: SQLiteDBConnection, obj: Favicon) -> Int? {
        var err: NSError? = nil
        let id = self.insert(db, item: obj, err: &err)
        if id >= 0 {
            obj.id = id
            return id
        }

        if obj.id == nil {
            let id = getIDFor(db, obj: obj)
            obj.id = id
            return id
        }

        return obj.id
    }

    func getCleanupCommands() -> (String, Args?) {
        return ("DELETE FROM \(TableFavicons) " +
            "WHERE \(TableFavicons).id NOT IN (" +
            "SELECT faviconID FROM \(TableFaviconSites) " +
            "UNION ALL " +
            "SELECT faviconID FROM \(TableBookmarksLocal) WHERE faviconID IS NOT NULL " +
            "UNION ALL " +
            "SELECT faviconID FROM \(TableBookmarksMirror) WHERE faviconID IS NOT NULL" +
            ")", nil)
    }
}

extension BrowserProfile {

    public func braveShieldPerDomain(url: NSURL) -> Deferred<Maybe<BraveShieldState>> {
        struct Static {
            static var braveShieldForDomain = 0
        }
        var x = Static.braveShieldForDomain
        return self.syncManager.syncClientsThenTabs()
            >>> { self.remoteClientsAndTabs.getClientsAndTabs() }
    }
}

public class BraveShieldState {
    public enum StateEnum: Int  {
        case AllOn = 0
        case AdblockOff = 1
        case TPOff = 2
        case HTTPSEOff = 4
        case SafeBrowingOff = 8
    }

    var state = StateEnum.AllOn.rawValue

    func isOnAdBlock() -> Bool {
        return state & StateEnum.AdblockOff.rawValue == 0
    }

    func isOnTrackingProtection() -> Bool {
        return state & StateEnum.TPOff.rawValue == 0
    }

    func isOnHTTPSE() -> Bool {
        return state & StateEnum.HTTPSEOff.rawValue == 0
    }

    func isOnSafeBrowsing() -> Bool {
        return state & StateEnum.SafeBrowingOff.rawValue == 0
    }

    func setState(states:[StateEnum]) {
        state = 0
        for s in states {
            state |= s.rawValue
        }
    }
}