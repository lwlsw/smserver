import Foundation
import SQLite3
import SwiftUI
import Photos
import os

class ChatDelegate {
    var debug: Bool = UserDefaults.standard.object(forKey: "debug") as? Bool ?? false
    var past_latest_texts = [String:String]()
    var newest_texts = [String]()
    let prefix = "SMServer_app: "
    
    static let imageStoragePrefix = "/private/var/mobile/Library/SMS/Attachments/"
	static let photoStoragePrefix = "/var/mobile/Media/DCIM/"
    static let userHomeString = "/private/var/mobile/"
    
    func log(_ s: String) {
        /// Logs to syslog/console
        os_log("%{public}@%{public}@", log: OSLog(subsystem: "com.ianwelker.smserver", category: "debugging"), type: .debug, self.prefix, s)
    }
    
    func createConnection(connection_string: String = "/private/var/mobile/Library/SMS/sms.db") -> OpaquePointer? {
        /// This simply returns an opaque pointer to the database at $connection_string, allowing for sqlite connections.
        
        var db: OpaquePointer?
        let connection_url = URL(fileURLWithPath: connection_string)
        
        /// Open the database
        guard sqlite3_open(connection_url.path, &db) == SQLITE_OK else {
            self.log("WARNING: error opening database")
            sqlite3_close(db)
            db = nil
            return db
        }
        
        if self.debug {
            self.log("opened database")
        }
        
        /// Return pointer to the database
        return db
    }
    
	func selectFromSql(db: OpaquePointer?, columns: [String], table: String, condition: String = "", num_items: Int = -1, offset: Int = 0) -> [[String:String]] {
        /// This executes an SQL query, specifically 'SELECT $columns from $table $condition LIMIT $offset, $num_items', on $db
        
        /// Construct the query
        var sqlString = "SELECT "
        for i in columns {
            sqlString += i
            if i != columns[columns.count - 1] {
                sqlString += ", "
            }
        }
        sqlString += " from " + table
        if condition != "" {
            sqlString += " " + condition
        }
        if num_items > 0 || offset != 0 {
            sqlString += " LIMIT \(offset), \(String(num_items))"
        }
        sqlString += ";"
        
        if self.debug {
            self.log("full sql query: " + sqlString)
        }
        
        var statement: OpaquePointer?
        
        if self.debug {
            self.log("opened statement")
        }
        
        /// Prepare the database for querying $sqlString
        if sqlite3_prepare_v2(db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            self.log("WARNING: error preparing select: \(errmsg)")
        }
        
        var main_return = [[String:String]]()
        
        /// Separate sections for num_items > 0 and num_items == 0 because if num_items == 0, then it gets all the items,
        /// but otherwise it just gets as many as were asked for
        if num_items > 0 {
            var i = 0
            /// for each row, up to num_items rows
            while sqlite3_step(statement) == SQLITE_ROW && i < num_items {
                var minor_return = [String:String]()
                /// for every column in the row
                for j in 0..<columns.count {
                    var tiny_return = ""
                    /// Get the string for the specific column
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    }
                    /// add it to return value
                    minor_return[columns[j]] = tiny_return
                }
                /// Add it to return value
                main_return.append(minor_return)
                i += 1
            }
        } else {
            /// While we can get a row
            while sqlite3_step(statement) == SQLITE_ROW {
                var minor_return = [String:String]()
                /// For each column in the row
                for j in 0..<columns.count {
                    var tiny_return = ""
                    /// Get the text
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    }
                    minor_return[columns[j]] = tiny_return
                }
                main_return.append(minor_return)
            }
        }
        
        /// Finalize; has to be done after getting info.
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            self.log("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        if self.debug {
            self.log("destroyed statement")
        }
        
        /// Since we passed $db in as a parameter, we don't close the database here, but rather in the function where $db was constructed
        return main_return
    }
    
    func selectFromSqlWithId(db: OpaquePointer?, columns: [String], table: String, identifier: String, condition: String = "", num_items: Int = 0) -> [String: [String:String]] {
        /// This does the same thing as selectFromSql, but returns a dictionary, for O(1) access, instead of an array, for when it doesn't need to be sorted.
        /// Just look at the selectFromSql function to see what each line does 'cause they're basically identical.
        
        var sqlString = "SELECT "
        for i in columns {
            sqlString += i
            if i != columns[columns.count - 1] {
                sqlString += ", "
            }
        }
        sqlString += " from " + table
        if condition != "" {
            sqlString += " " + condition
        }
        if num_items != 0 {
            sqlString += " LIMIT \(String(num_items))"
        }
        sqlString += ";"
        
        if self.debug {
            self.log("full sql query: " + sqlString)
        }
        
        var statement: OpaquePointer?
        
        if self.debug {
            self.log("opened statement")
        }
        
        if sqlite3_prepare_v2(db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            self.log("WARNING: error preparing select: \(errmsg)")
        }
        
        var main_return = [String: [String:String]]()
        
        if num_items != 0 {
            var i = 0
            while sqlite3_step(statement) == SQLITE_ROW && i < num_items {
                var minor_return = [String:String]()
                var minor_identifier = ""
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    }
                    minor_return[columns[j]] = tiny_return
                    if columns[j] == identifier {
                        minor_identifier = tiny_return
                    }
                }
                main_return[minor_identifier] = minor_return
                i += 1
            }
        } else {
            while sqlite3_step(statement) == SQLITE_ROW {
                var minor_return = [String:String]()
                var minor_identifier = ""
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    }
                    minor_return[columns[j]] = tiny_return
                    if columns[j] == identifier {
                        minor_identifier = tiny_return
                    }
                }
                main_return[minor_identifier] = minor_return
            }
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            self.log("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        if self.debug {
            self.log("destroyed statement")
        }
        
        return main_return
    }
    
    func checkIfConnected() -> Bool {
        /// Simple function to check if you can read values from the database.
        
        if self.debug {
            self.log("Checking if connected")
        }
        
        var db = createConnection()
        
        let checker = selectFromSql(db: db, columns: ["ROWID"], table: "chat", num_items: 1)
        
        /// Close; prevents memory leaks
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        return checker.count != 0
    }
    
    func parsePhoneNum(num: String) -> String {
        /// This returns a string with SQL wildcards so that you can enter a phone number (e.g. +12837291837) and match it with something like +1 (283) 729-1837.
        /// It'll probably only work reliably with American phone numbers but it's not a crucial part (only used to get names),
        /// so I'm not gonna put too much effort into localization; submit a pull request if it doesn't work for yours
        
        if self.debug {
            self.log("parsing phone number for \(num)")
        }
        
        /// remove everything but numbers
        let new_num = num.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if new_num.count == 0 {
            return ""
        }
        
        if num.count <= 7 {
            let num_zero = new_num[new_num.startIndex ..< (new_num.index(new_num.startIndex, offsetBy: 3, limitedBy: new_num.endIndex) ?? new_num.endIndex)]
            let num_one = new_num[(new_num.index(new_num.startIndex, offsetBy: 3, limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< new_num.endIndex]
            return num_zero + "_" + num_one
        } else {
            let num_zero = String(new_num[new_num.startIndex ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 10), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_one = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 10), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 7), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_two = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 7), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 4), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_three = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 4), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< new_num.endIndex])
            /// num_zero is country code, num_one is american area code, num_two is first 3 digits of regular number, and num_three is last 4 digits of regular number
            return "%" + num_zero + "%" + num_one + "%" + num_two + "%" + num_three + "%"
        }
    }
    
    func getDisplayName(chat_id: String) -> String {
        /// This does the same thing as getDisplayName, but doesn't take db as an argument. This allows for fetching of a single name,
        /// when you don't need to get a lot of names at once.
        
        if self.debug {
            self.log("Getting display name for \(chat_id)")
        }
        
        /// Connect to contact database
        var db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        
        /// get name
        let name = getDisplayNameWithDb(db: db, chat_id: chat_id)
        
        /// close
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        if self.debug {
            self.log("destroyed db")
        }
        
        return name
    }
    
    func getDisplayNameWithDb(db: OpaquePointer?, chat_id: String) -> String {
        /// Gets the first + last name of a contact with the phone number or email of $chat_id
        
        if self.debug {
            self.log("Getting display name for \(chat_id) with db")
        }
        
        var display_name_array = [[String:String]]()
        
        if chat_id.contains("@") { /// if an email
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"")
        } else {
            /// parse phone number for better compatibility
            let parsed_num = parsePhoneNum(num: chat_id)
            /// get first name and last name
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
            
        }
        
        if display_name_array.count != 0 {
            /// combine first name and last name
            let full_name: String = (display_name_array[0]["c0First"] ?? "no_first") + " " + (display_name_array[0]["c1Last"] ?? "no_last")
            
            if self.debug {
                self.log("full name for \(chat_id) is \(full_name)")
            }
            
            return full_name
        }
        
        return ""
    }
    
    func getGroupRecipientsWithDb(contact_db: OpaquePointer?, db: OpaquePointer?, ci: String) -> [String] {
        
        if self.debug {
            self.log("Getting group chat recipients for \(ci)")
        }
        
        let recipients = selectFromSql(db: db, columns: ["id"], table: "handle", condition: "WHERE ROWID in (SELECT handle_id from chat_handle_join WHERE chat_id in (SELECT ROWID from chat where chat_identifier is \"\(ci)\"))")
        
        var ret_val = [String]()
        
        for i in recipients {
            /// Ok this is super lazy but I don't actually return all the group recipients, I just get the first two, then add '...' onto the end
            /// Maybe I'll improve this in the future when I get better at JS & CSS and can display it nicely on the web interface
            if recipients.count > 2 && i == recipients[2] {
                ret_val.append("...")
                break
            }
            
            /// get name for person
            let ds = getDisplayNameWithDb(db: contact_db, chat_id: i["id"] ?? "")
            ret_val.append((ds == "" ? i["id"] : ds) ?? "")
        }
        
        if self.debug {
            self.log("Finished retrieving recipients for \(ci)")
        }
        
        return ret_val
    }
    
    func loadMessages(num: String, num_items: Int, offset: Int = 0) -> [[String:String]] {
        /// This loads the latest $num_items messages from/to $num, offset by $offset.
        
        if self.debug {
            self.log("getting messages for \(num)")
        }
        
        /// Create connection to text and contact databases
        var db = createConnection()
        var contact_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        
        /// Get the most recent messages and all their relevant metadata from $num
        var messages = selectFromSql(db: db, columns: ["ROWID", "text", "is_from_me", "date", "service", "cache_has_attachments", "handle_id"], table: "message", condition: "WHERE ROWID IN (SELECT message_id FROM chat_message_join WHERE chat_id IN (SELECT ROWID from chat WHERE chat_identifier is \"\(num)\") ORDER BY message_date DESC) ORDER BY date DESC", num_items: num_items, offset: offset)
        
        /// check if it's a group chat
        let is_group = num.prefix(4) == "chat"
        
        /// for each message
        for i in 0..<messages.count {
            /// if it has attachments
            if messages[i]["cache_has_attachments"] == "1" && messages[i]["ROWID"] != nil {
                let a = getAttachmentFromMessage(mid: messages[i]["ROWID"]!) /// get list of attachments
                var file_string = ""
                var type_string = ""
                if self.debug {
                    print(prefix)
                    print(a)
                }
                for i in 0..<a.count {
                    /// use ':' as separater between attachments 'cause you can't have a filename in iOS that contains it (I think?)
                    file_string += a[i][0] + (i != a.count ? ":" : "")
                    type_string += a[i][1] + (i != a.count ? ":" : "")
                }
                messages[i]["attachment_file"] = file_string
                messages[i]["attachment_type"] = type_string
            }
            
            /// get names for each message's sender if it's a group chat
            if is_group && messages[i]["is_from_me"] == "0" && messages[i]["handle_id"] != nil {
                
                let handle = selectFromSql(db: db, columns: ["id"], table: "handle", condition: "WHERE ROWID is \(messages[i]["handle_id"]!)", num_items: 1)
                
                if handle.count > 0 {
                    let name = getDisplayNameWithDb(db: contact_db, chat_id: handle[0]["id"]!)
                    
                    messages[i]["sender"] = name
                }
            } else {
                /// if it's not a group chat, or it's from me, or it doesn't have information on who sent it
                messages[i]["sender"] = "nil"
            }
        }
        
        /// close dbs
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        if sqlite3_close(contact_db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        contact_db = nil
        
        if self.debug {
            self.log("destroyed db")
            self.log("returning messages!")
        }
        
        return messages
    }
    
    func loadChats(num_to_load: Int, offset: Int = 0) -> [[String:String]] {
        /// This loads the most recent $num_to_load conversations, offset by $offset
        
        if self.debug {
            self.log("Getting chats")
        }
        
        /// Create connections
        var db = createConnection()
        var contacts_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        
        /// Get relevant information to construct most recent chats
        let messages = selectFromSqlWithId(db: db, columns: ["ROWID", "is_read", "is_from_me", "text", "item_type", "date_read", "date"], table: "message", identifier: "ROWID", condition: "WHERE ROWID in (select message_id from chat_message_join where message_date in (select max(message_date) from chat_message_join group by chat_id) order by message_date desc)")
        let chat_ids_ordered = selectFromSql(db: db, columns: ["chat_id", "message_id"], table: "chat_message_join", condition: "where message_date in (select max(message_date) from chat_message_join group by chat_id) order by message_date desc", num_items: num_to_load, offset: offset)
        let chats = selectFromSqlWithId(db: db, columns: ["ROWID", "chat_identifier", "display_name"], table: "chat", identifier: "ROWID", condition: "WHERE ROWID in (select chat_id from chat_message_join where message_date in (select max(message_date) from chat_message_join group by chat_id))")
        
        var chats_array = [[String:String]]()
        var already_selected = [String:Int]() /// Just making it a dictionary so I have O(1) access instead of iterating through, as with an array
        
        if self.debug {
            self.log("len messages: \(messages.count), len chat_ids_ordered: \(chat_ids_ordered.count), len chats: \(chats.count)")
        }
        
        /*let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric*/
        
        /// chat_ids_ordered has a list of the most recent chat_ids that you have talked with (and their most recent message), ordered by most recent
        for i in chat_ids_ordered {
            
            if chats[i["chat_id"] ?? ""] == nil { continue }
            
            /// get the chat information for the current chat_id
            var new_chat = chats[i["chat_id"]!]
            
            /// get chat_identifier. Should be also equal to i["chat_id"]
            let ci = new_chat?["chat_identifier"]
            
            if self.debug {
                self.log("Beginning to iterate through chats for \(String(describing: ci))")
            }
            
            /// If we've already got the information for this conversation, continue
            if already_selected[ci ?? "no_chat"] != nil || ci == nil { continue }
            
            /// message information of the most recent message message between you and this conversation
            let mwid = messages[i["message_id"] ?? "nil"]
            
            new_chat!["has_unread"] = "false"
            
            /// If all these specific parameters are true, then it is unread. Yeah, I wish it was just mwid?["is_read"], too.
            if mwid?["is_from_me"] == "0" && mwid?["date_read"] == "0" && mwid?["text"] != nil && mwid?["is_read"] == "0" && mwid?["item_type"] == "0" {
                new_chat!["has_unread"] = "true"
            }
            
            /// Content of the most recent text
            new_chat?["latest_text"] = mwid?["text"]
            
            /// Time when the most recent text was sent
            new_chat?["time_marker"] = mwid?["date"]
            
            /*let temp_int = Double(Int(mwid?["date"] ?? "0") ?? 0 / 1000000000)
            let ts: Double = temp_int + 978307200.0
            
            let date = Date(timeIntervalSince1970: ts)
            
            new_chat?["relative_time"] = formatter.string(for: date)*/ /// Will soon get relative date as opposed to explicit date
            
            /// Some group chats have a display name, no one-on-one conversations do. So just checking if it does have one.
            if new_chat?["display_name"]!.count == 0 {
                if ci?.prefix(4) == "chat" && !((ci?.contains("@")) ?? true) { /// Making sure it's a group chat
                    /// get recipients
                    let recipients = getGroupRecipientsWithDb(contact_db: contacts_db, db: db, ci: ci!)
                    
                    var display_val = ""
                    
                    for r in recipients {
                        display_val += r
                        if r != recipients[recipients.count - 1] {
                            display_val += ", "
                        }
                    }
                    
                    new_chat?["display_name"] = display_val
                } else {
                    /// get person's name
                    new_chat?["display_name"] = getDisplayNameWithDb(db: contacts_db, chat_id: ci ?? "")
                }
            }
            
            /// Append new chat to return array
            chats_array.append(new_chat ?? [String:String]())
            
            /// append chat_id to already_selected so that we know we don't have to check this chat_id again
            already_selected[ci ?? "no_chat"] = 0
            
            if self.debug {
                self.log("Finished iterating through chats for \(String(describing: ci))")
            }
        }
        
        /// close
        if sqlite3_close(contacts_db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        contacts_db = nil
        
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        if self.debug {
            self.log("destroyed db")
        }
        
        return chats_array
    }
    
    func returnImageData(chat_id: String) -> Data {
        /// This does the same thing as returnImageDataDB, but without the contact_db and image_db as arguments, if you just need to get like 1 image
        
        if self.debug {
            self.log("Getting image data for chat_id \(chat_id)")
        }
        
        /// Make connections
        var contact_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        var image_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBookImages.sqlitedb")
        
        /// get image data with dbs as parameters
        let return_val = returnImageDataDB(chat_id: chat_id, contact_db: contact_db!, image_db: image_db!)
        
        /// close
        if sqlite3_close(contact_db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        contact_db = nil
        
        if sqlite3_close(image_db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        image_db = nil
        
        return return_val
    }
    
    func returnImageDataDB(chat_id: String, contact_db: OpaquePointer, image_db: OpaquePointer) -> Data {
        /// This returns the profile picture for someone with the phone number or email $chat_id as pure image data
        
        if self.debug {
            self.log("Getting image data with db for chat_id \(chat_id)")
        }
        
        var docid = [[String:String]]()
        
        /// get docid. docid is the identifier that corresponds to each contact, allowing for us to get their image
        if chat_id.contains("@") {
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"", num_items: 1)
        } else {
            let parsed_num = parsePhoneNum(num: chat_id)
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
        }
        
        /// Use default profile if you don't have them in your contacts
        if docid.count == 0 {
            
            let image_dat = UIImage(named: "profile")
            let pngdata = (image_dat?.pngData())!
            
            return pngdata
        }
            
        /// each contact image is stored as a blob in the sqlite database, not as a file.
        /// That's why we need a special query to get it, and can't use the selectFromSql function(s).
        let sqlString = "SELECT data FROM ABThumbnailImage WHERE record_id=\"\(String(describing: docid[0]["docid"]!))\""
        
        var statement: OpaquePointer?
        
        if self.debug {
            self.log("opened statement")
        }
        
        if sqlite3_prepare_v2(image_db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            self.log("WARNING: error preparing select: \(errmsg)")
        }
        
        var pngdata: Data;
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if let tiny_return_blob = sqlite3_column_blob(statement, 0) {
                
                /// Getting the data
                let len: Int32 = sqlite3_column_bytes(statement, 0)
                let dat: NSData = NSData(bytes: tiny_return_blob, length: Int(len))
                
                /// Putting it into UIImage format, then grabbing the image from that
                let image_w_dat = UIImage(data: Data(dat))
                pngdata = (image_w_dat?.pngData())!
                
            } else {
                if self.debug {
                    self.log("No profile picture found. Using default.")
                }
                
                /// Use default profile if you don't have a profile image set for them
                let image_dat = UIImage(named: "profile")
                pngdata = (image_dat?.pngData())!
            }
        } else {
            
            /// Just a backup; use default image
            let image_dat = UIImage(named: "profile")
            pngdata = (image_dat?.pngData())!
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            self.log("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        if self.debug {
            self.log("destroyed statement")
        }
        
        return pngdata
    }
    
    func setFirstTexts(address: String) { 
        /// This just clears out the newest_texts array so that in case a new text was received before someone established a connection
        /// it won't show that as a new text on the first ping.
        
        if self.debug {
            self.log("Setting first texts")
        }
        
        newest_texts = [String]()
    }
    
    func setNewTexts(_ chat_id: String) {
        /// uhhh can't remember what this does but I think it's deprecated
        newest_texts.removeAll(where: {$0 == chat_id})
        
        newest_texts.append(chat_id)
    }
    
    func getAttachmentFromMessage(mid: String) -> [[String]] {
        /// This returns the file path for all attachments associated with a certain message with the message_id of $mid
        
        if self.debug {
            self.log("Gettig attachment for mid \(mid)")
        }
        
        /// create connection, get attachments information
        var db = createConnection()
        let file = selectFromSql(db: db, columns: ["filename", "mime_type", "hide_attachment"], table: "attachment", condition: "WHERE ROWID in (SELECT attachment_id from message_attachment_join WHERE message_id is \(mid))")
        
        var return_val = [[String]]()
        
        if self.debug {
            self.log("attachment file length: \(String(file.count))")
        }
        
        if file.count > 0 {
            for i in file {
                
                /// get the path of the attachment minus the attachment storage prefix ("/private/var/mobile/Library/SMS/Attachments/")
                let suffixed = String(i["filename"]?.dropFirst(ChatDelegate.imageStoragePrefix.count - ChatDelegate.userHomeString.count + 2) ?? "")
                //suffixed = suffixed.replacingOccurrences(of: "/", with: "._.")
                let type = i["mime_type"] ?? ""
                
                /// Append to return array
                return_val.append([suffixed, type])
            }
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        return return_val
    }
    
    func getAttachmentType(path: String) -> String {
        /// This gets the file type of the attachment at $path
        
        if self.debug {
            self.log("Getting attachment type for @ \(path)")
        }
        
        //let new_path = path.replacingOccurrences(of: "._.", with: "/")
		//let new_path = path
        
        var db = createConnection()
        let file_type_array = selectFromSql(db: db, columns: ["mime_type"], table: "attachment", condition: "WHERE filename like \"%\(path)%\"", num_items: 1)
        var return_val = "image/jpeg" /// Most likely thing
        
        if file_type_array.count > 0 {
            return_val = file_type_array[0]["mime_type"]!
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            self.log("WARNING: error closing database")
        }

        db = nil
        
        return return_val
    }
    
    func getAttachmentDataFromPath(path: String) -> Data {
        /// This returns the pure data of a file (attachment) at $path
        
        if self.debug {
            self.log("Getting attachment data from path \(path)")
        }
        
        //let parsed_path = path.replacingOccurrences(of: "._.", with: "/").replacingOccurrences(of: "../", with: "") ///Prevents LFI
		let parsed_path = path.replacingOccurrences(of: "../", with: "") /// To prevent LFI
        
        do {
            /// Pretty strsightforward -- get data and return it
            let attachment_data = try Data.init(contentsOf: URL(fileURLWithPath: ChatDelegate.imageStoragePrefix + parsed_path))
            return attachment_data
        } catch {
            self.log("WARNING: failed to load image for path \(ChatDelegate.imageStoragePrefix + path)")
            return Data.init(capacity: 0)
        }
    }
	
	func searchForString(term: String, case_sensitive: Bool = false, bridge_gaps: Bool = true) -> [String:[[String:String]]]{
        /// This gets all texts with $term in them; case_sensitive and bridge_gaps are customization options
        
        /// Create Connections
		var db = createConnection()
		var contact_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
		
        /// Replacing percentages with escaped so that they don't act as wildcard characters
        var upperTerm = term.replacingOccurrences(of: "%", with: "\\%")
        
        /// replace spaces with wildcard characters if bridge_gaps == true
		if bridge_gaps { upperTerm = upperTerm.split(separator: " ").joined(separator: "%") }
		
		var return_texts = [String:[[String:String]]]()
		
		let texts = selectFromSql(db: db, columns: ["ROWID", "text", "service", "date", "cache_has_attachments"], table: "message", condition: "WHERE text like \"%\(upperTerm)%\"")
		
		for var i in texts {
			if case_sensitive && !(i["text"]?.contains(term) ?? true) { continue } /// Sqlite3 library can't set like to be case-sensitive. Must manually check.
			
			if i["date"] != nil {
				let date: Int = Int(String(i["date"] ?? "0")) ?? 0
				let new_date: Int = date / 1000000000
				let timestamp: Int = new_date + 978307200
				i["date"] = String(timestamp) /// Turns it into unix timestamp for easier use
			}
			
            /// get sender for this text
			let handle = selectFromSql(db: db, columns: ["chat_identifier", "display_name"], table: "chat", condition: "WHERE ROWID in (SELECT chat_id from chat_message_join WHERE message_id is \(i["ROWID"] ?? ""))", num_items: 1)
			var chat = ""
			
			if handle.count > 0 {
				if handle[0]["display_name"]?.count == 0 {
					chat = handle[0]["chat_identifier"] ?? "(null)"
				} else {
					chat = "Group: " + (handle[0]["display_name"] ?? "(null)")
				}
			}
			
            /// Add this text onto the list of texts from this person that match term
			if return_texts[chat] == nil {
				return_texts[chat] = [i]
			} else {
				return_texts[chat]?.append(i)
			}
		}
		
        /// Replace Group name with list of recipients
		for i in Array(return_texts.keys) {
			if i.prefix(7) != "Group: " {
				let name = getDisplayNameWithDb(db: contact_db, chat_id: i)
				
				if name.count != 0 {
					return_texts[name] = return_texts[i]
					return_texts.removeValue(forKey: i)
				}
			}
		}
		
        /// close
		if sqlite3_close(db) != SQLITE_OK {
			self.log("WARNING: error closing database")
		}

		db = nil
		
		if sqlite3_close(contact_db) != SQLITE_OK {
			self.log("WARNING: error closing database")
		}

		contact_db = nil
		
		return return_texts
	}
	
	func getPhotoList(num: Int = 40, offset: Int = 0, most_recent: Bool = true) -> [[String: String]] { /// Gotta include stuff like favorite
		/// This gets a list of the $num (most_recent ? most recent : oldest) photos, offset by $offset.
		
        /// make sure that we have access to the photos library
		if PHPhotoLibrary.authorizationStatus() != PHAuthorizationStatus.authorized { return [[String:String]]() }
		
		var ret_val = [[String:String]]()
		let fetchOptions = PHFetchOptions()
        /// sort photos by most recent
		fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !most_recent)]
		fetchOptions.fetchLimit = num + offset
		
		let requestOptions = PHImageRequestOptions()
		requestOptions.isSynchronous = true
		requestOptions.isNetworkAccessAllowed = true
		
        /// get images!
		let result = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
		
		let total = result.countOfAssets(with: PHAssetMediaType.image)
        print(result)
		
		//for i in offset..<(total + offset) {
        for i in offset..<total {
            var next = false;
			let dispatchGroup = DispatchGroup()
			
			var local_result = [String:String]()
            
			let image = result.object(at: i)
			var img_url = ""
            print(image)
			
			dispatchGroup.enter() /// This whole dispatchGroup this is necessary to get the completion handler to run synchronously with the rest
			
			image.getURL(completionHandler: { url in
                /// get url of each image
				img_url = url!.path.replacingOccurrences(of: "/var/mobile/Media/DCIM/", with: "")
                print("leaving: \(img_url)")
				dispatchGroup.leave()
			})
			
			dispatchGroup.notify(queue: DispatchQueue.main) {
                /// append vals to return value
                print("entering: \(img_url)")
				local_result["URL"] = img_url
				local_result["is_favorite"] = String(image.isFavorite)
				
				ret_val.append(local_result)
                print("appended: \(img_url)")
                next = true
			}
            
            /// This is hacky and kinda hurts performance but it seems the most reliable way to load images in order + with the amount requested.
            while next == false {}
		}
		
		return ret_val
	}
	
	func getPhotoDatafromPath(path: String) -> Data {
		/// This returns the pure data of a photo at $path
		
		if self.debug {
			self.log("Getting photo data from path \(path)")
		}
		
		let parsed_path = path.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "../", with: "") /// To prevent LFI
		
		do {
            /// get and return photo data
			let photo_data = try Data.init(contentsOf: URL(fileURLWithPath: ChatDelegate.photoStoragePrefix + parsed_path))
			return photo_data
		} catch {
			self.log("WARNING: failed to load photo for path \(ChatDelegate.photoStoragePrefix + path)")
			return Data.init(capacity: 0)
		}
	}
}

extension PHAsset {

	func getURL(completionHandler : @escaping ((_ responseURL : URL?) -> Void)){
        /// This allows for retrieval of a PHAsset's URL in the filesystem.
        
		if self.mediaType == .image {
			let options: PHContentEditingInputRequestOptions = PHContentEditingInputRequestOptions()
			options.canHandleAdjustmentData = {(adjustmeta: PHAdjustmentData) -> Bool in
				return true
			}
			self.requestContentEditingInput(with: options, completionHandler: {(contentEditingInput: PHContentEditingInput?, info: [AnyHashable : Any]) -> Void in
				completionHandler(contentEditingInput!.fullSizeImageURL as URL?)
			})
		} else if self.mediaType == .video {
			let options: PHVideoRequestOptions = PHVideoRequestOptions()
			options.version = .original
			PHImageManager.default().requestAVAsset(forVideo: self, options: options, resultHandler: {(asset: AVAsset?, audioMix: AVAudioMix?, info: [AnyHashable : Any]?) -> Void in
				if let urlAsset = asset as? AVURLAsset {
					let localVideoUrl: URL = urlAsset.url as URL
					completionHandler(localVideoUrl)
				} else {
					completionHandler(nil)
				}
			})
		}
	}
}
