import Foundation
import Deferred
import Shared
import Storage

struct BraveShieldTableRow {
    var baseDomain = ""
    var shieldState = BraveShieldState.StateEnum.AllOn.rawValue
}

class BraveShieldTable: GenericTable<BraveShieldTableRow> {
    static let tableName = "brave_shield_per_domain"
    static let colDomain = "base_domain"
    static let colState = "state"

    var db: BrowserDB!
    static func initialize(db: BrowserDB) -> BraveShieldTable? {
        let table = BraveShieldTable()
        table.db = db
        if !db.createOrUpdate(table) {
            return nil
        }
        return table
    }

    override var name: String { return BraveShieldTable.tableName }
    override var rows: String { return "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        " \(BraveShieldTable.colDomain) TEXT NOT NULL UNIQUE, " +
        " \(BraveShieldTable.colState) TINYINT NOT NULL DEFAULT 0 " }

    func getRowForUrl(url: NSURL) -> Deferred<Maybe<BraveShieldTableRow?>> {
        var err: NSError?

        let cursor = db.withReadableConnection(&err) { connection, _ -> Cursor<BraveShieldTableRow> in
            let opts = QueryOptions()
            opts.filter = url.baseDomain()
            return self.query(connection, options: opts)
        }

        if let err = err {
            cursor.close()
            return deferMaybe(DatabaseError(err: err))
        }

        let items = cursor.asArray()
        cursor.close()
        return deferMaybe(items.first)
    }

    func makeArgs(item: BraveShieldTableRow) -> [AnyObject?] {
        var args = [AnyObject?]()
        args.append(item.shieldState)
        args.append(item.baseDomain)
        return args
    }

    override func getInsertAndArgs(inout item: BraveShieldTableRow) -> (String, [AnyObject?])? {
        return ("INSERT INTO \(BraveShieldTable.tableName) (\(BraveShieldTable.colState), \(BraveShieldTable.colDomain)) VALUES (?,?)", makeArgs(item))
    }

    override func getUpdateAndArgs(inout item: BraveShieldTableRow) -> (String, [AnyObject?])? {
        return ("UPDATE \(BraveShieldTable.tableName) SET \(BraveShieldTable.colState) = ? WHERE \(BraveShieldTable.colDomain) = ?", makeArgs(item))
    }

    override func getDeleteAndArgs(inout item: BraveShieldTableRow?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let item = item {
            args.append(item.baseDomain)
            return ("DELETE FROM \(BraveShieldTable.tableName) WHERE \(BraveShieldTable.colDomain) = ?", args)
        }
        return ("DELETE FROM \(BraveShieldTable.tableName)", [])
    }

    override var factory: ((row: SDRow) -> BraveShieldTableRow)? {
        return { row -> BraveShieldTableRow in
            var item = BraveShieldTableRow()
            if let domain = row[BraveShieldTable.colDomain] as? String, state = row[BraveShieldTable.colState] as? Int {
                item.baseDomain = domain
                item.shieldState = state
            }
            return item
        }
    }

    override func getQueryAndArgs(options: QueryOptions?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let filter: AnyObject = options?.filter {
            args.append("%\(filter)%")
            return ("SELECT \(BraveShieldTable.colState), \(BraveShieldTable.colDomain) FROM \(BraveShieldTable.tableName) WHERE \(BraveShieldTable.colDomain) LIKE ?", args)
        }
        return ("SELECT \(BraveShieldTable.colState), \(BraveShieldTable.colDomain) FROM \(BraveShieldTable.tableName)", args)
    }
}


var braveShieldForDomain:BraveShieldTable? = nil

extension BrowserProfile {

    public func braveShieldPerBaseDomain(url: NSURL) -> Deferred<BraveShieldState?> {
        let deferred = Deferred<BraveShieldState?>()

        succeed().upon() {_ in // move off main thread
            if braveShieldForDomain == nil {
                braveShieldForDomain = BraveShieldTable.initialize(self.db)
            }

            braveShieldForDomain?.getRowForUrl(url).upon {
                result in
                if let success = result.successValue {
                    deferred.fill(BraveShieldState(state: success?.shieldState))
                } else {
                    deferred.fill(nil)
                }
            }
        }

        return deferred
    }

    public func setBraveShieldForBaseDomain(domain: String, state: Int) {
        succeed().upon() { _ in
            if braveShieldForDomain == nil {
                braveShieldForDomain = BraveShieldTable.initialize(self.db)
            }

            var t = BraveShieldTableRow()
            t.baseDomain = domain
            t.shieldState = state
            var err: NSError?
            self.db.transaction(synchronous: true, err: &err) { (connection, inout err:NSError?) -> Bool in
                if state == 0 {
                    braveShieldForDomain?.delete(connection, item: t, err: &err)
                    return true
                }

                let id = braveShieldForDomain?.insert(connection, item: t, err: &err)
                if id < 0 {
                    braveShieldForDomain?.update(connection, item: t, err: &err)
                }
                return true
            }
        }
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

    public init?(state: Int?) {
        if let state = state {
            self.state = state
        } else {
            return nil
        }
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