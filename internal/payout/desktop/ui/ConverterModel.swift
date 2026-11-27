import Combine

import Foundation

struct SavedPayment: Codable, Equatable {
    var id: UInt64
    var revision: UInt64
    var name: String?
    var cents: Int64
    var request_id: String?
}

struct Payment: Identifiable {
    let id: UUID
    var name: String
    var amount: String
    var saved: SavedPayment?
}

private enum Action: String, Encodable {
    case read, refresh, add, edit, remove
}

private struct Request: Encodable {
    let version = 1
    let provider: String
    let action: Action
    var payment: SavedPayment?
    var name: String?
    var amount: String?
    var request_id: String?
}

private struct Snapshot: Decodable {
    var version: Int
    var error: String?
    var name: String
    var currency: String
    var language: String
    var rate: String
    var market: String
    var checked: Date
    var stale: Bool
    var payments: [SavedPayment]?
    var payment_id: UInt64?
}

struct Connection {
    let binary: String
    let provider: String
    let config: String
    let cache: String
    let wrapper: String
}

private struct Session: Decodable {
    let provider: String
    let cache: String
    let wrapper: String
}

@MainActor
final class ConverterModel: ObservableObject {
    @Published var payments: [Payment] = []
    @Published var simulation = ""
    @Published var keypad: KeypadTarget?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var removed: Payment?
    @Published private var snapshot: Snapshot?
    private var connection: Connection?

    var currency: String { snapshot?.currency ?? "" }
    var providerName: String { snapshot?.name ?? "" }
    var portuguese: Bool { snapshot?.language == "pt" }
    var ready: Bool { snapshot != nil }
    var stale: Bool { snapshot?.stale == true }
    var checked: Date? { rate == nil ? nil : snapshot?.checked }
    var rate: Decimal? { decimal(snapshot?.rate ?? "") }
    var market: Decimal? { decimal(snapshot?.market ?? "") }
    var hasUnsavedChanges: Bool { payments.contains(where: dirty) }

    func text(_ pt: String, _ en: String) -> String { portuguese ? pt : en }

    func select(_ url: URL) {
        guard url.scheme == "usdbrl-converter", url.host == "open" else { return }
        load()
    }

    func load() {
        let config = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let data = try? Data(contentsOf: config.appendingPathComponent("converter-session.json")),
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            error = "state"
            return
        }
        guard !busy, payments.allSatisfy({ $0.saved != nil && !dirty($0) }) else {
            if connection?.provider != session.provider {
                error = "pending"
            }
            return
        }
        connect(Connection(binary: config.appendingPathComponent("bin/usdbrl").path,
                           provider: session.provider, config: config.path,
                           cache: session.cache, wrapper: session.wrapper))
    }

    func add() -> UUID {
        let row = Payment(id: UUID(), name: "", amount: "", saved: nil)
        payments.append(row)
        return row.id
    }

    func reload() {
        guard !busy, let connection else { return }
        connect(connection)
    }

    func canSave(_ row: Payment) -> Bool {
        dirty(row) && amount(row.amount) != nil
    }

    func save(_ id: UUID) {
        guard !busy, let row = payments.first(where: { $0.id == id }), dirty(row), let connection else { return }
        guard amount(row.amount) != nil else {
            if row.saved != nil || !row.amount.isEmpty { error = "invalid" }
            return
        }
        let request = Request(provider: connection.provider, action: row.saved == nil ? .add : .edit,
                              payment: row.saved, name: row.name, amount: normalize(row.amount),
                              request_id: row.saved == nil ? row.id.uuidString : nil)
        perform(request) { [self] result in
            guard result.error == nil, let fresh = savedPayment(in: result),
                  let index = payments.firstIndex(where: { $0.id == id }) else { return }
            payments[index] = draft(fresh, id: id)
            refreshMenu(connection.wrapper)
        }
    }

    func remove(_ id: UUID) {
        guard let row = payments.first(where: { $0.id == id }) else { return }
        guard let saved = row.saved, let connection else {
            payments.removeAll { $0.id == id }
            return
        }
        perform(Request(provider: connection.provider, action: .remove, payment: saved)) { [self] result in
            guard result.error == nil else { return }
            removed = row
            payments.removeAll { $0.id == id }
            refreshMenu(connection.wrapper)
        }
    }

    func undo() {
        guard let row = removed, let saved = row.saved, let connection else { return }
        perform(Request(provider: connection.provider, action: .add, name: saved.name,
                        amount: rawAmount(saved.cents), request_id: row.id.uuidString + "-undo")) { [self] result in
            guard result.error == nil, let fresh = savedPayment(in: result) else { return }
            payments.append(draft(fresh))
            removed = nil
            refreshMenu(connection.wrapper)
        }
    }

    func refresh() {
        guard let connection else { return }
        perform(Request(provider: connection.provider, action: .refresh)) { _ in
            refreshMenu(connection.wrapper)
        }
    }

    func amount(_ input: String) -> Decimal? {
        let text = normalize(input)
        guard text.range(of: #"^[0-9]{1,18}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = decimal(text), value > 0, value <= Decimal(Int64.max) / 100 else { return nil }
        return value
    }

    func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if portuguese && trimmed.range(of: #"^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]{1,2})?$"#, options: .regularExpression) != nil {
            return trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        if !portuguese && trimmed.range(of: #"^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil {
            return trimmed.replacingOccurrences(of: ",", with: "")
        }
        return trimmed.replacingOccurrences(of: ",", with: ".")
    }

    func keypadText(_ text: String) -> String {
        let value = normalize(text)
        return portuguese ? value.replacingOccurrences(of: ".", with: ",") : value
    }

    private func dirty(_ row: Payment) -> Bool {
        guard let saved = row.saved else { return true }
        return row.name != (saved.name ?? "") || amount(row.amount) != Decimal(saved.cents) / 100
    }

    private func connect(_ target: Connection) {
        connection = target
        perform(Request(provider: target.provider, action: .read)) { [self] result in
            guard result.error == nil else { return }
            payments = (result.payments ?? []).map { draft($0) }
            simulation = ""
            removed = nil
        }
    }

    private func perform(_ request: Request, completion: @escaping (Snapshot) -> Void) {
        guard !busy, let connection else { return }
        busy = true
        error = nil
        Task {
            let result = await Task.detached { try? invoke(connection, request) }.value
            if let result, result.version == 1 {
                snapshot = result
                error = result.error
                completion(result)
            } else {
                error = "state"
            }
            busy = false
        }
    }

    private func savedPayment(in result: Snapshot) -> SavedPayment? {
        guard let id = result.payment_id else { return nil }
        return result.payments?.first { $0.id == id }
    }

    private func draft(_ saved: SavedPayment, id: UUID = UUID()) -> Payment {
        let locale = Locale(identifier: portuguese ? "pt_BR" : "en_US")
        let amount = (Decimal(saved.cents) / 100).formatted(.number.precision(.fractionLength(2)).locale(locale))
        return Payment(id: id, name: saved.name ?? "", amount: amount, saved: saved)
    }
}

private func decimal(_ text: String) -> Decimal? {
    guard !text.isEmpty else { return nil }
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
}

private func rawAmount(_ cents: Int64) -> String {
    String(format: "%lld.%02lld", cents / 100, cents % 100)
}

private func invoke(_ connection: Connection, _ request: Request) throws -> Snapshot {
    let input = Pipe()
    let output = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: connection.binary)
    process.arguments = ["--converter-json"]
    var environment = ProcessInfo.processInfo.environment
    environment["USDBRL_CACHE_DIR"] = connection.cache
    environment["USDBRL_CONFIG_DIR"] = connection.config
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let data = try JSONEncoder().encode(request)
    try process.run()
    try input.fileHandleForWriting.write(contentsOf: data)
    try input.fileHandleForWriting.close()
    let deadline = DispatchWorkItem {
        if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: deadline)
    defer { deadline.cancel() }
    let reply = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Snapshot.self, from: reply)
}

private func refreshMenu(_ wrapper: String) {
    let original = URL(fileURLWithPath: wrapper)
    var name = original.lastPathComponent
    if !FileManager.default.fileExists(atPath: wrapper) {
        let directory = original.deletingLastPathComponent()
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let wrappers = candidates.filter {
            $0.range(of: #"^usdbrl\.[0-9]+[smhd]\.sh$"#, options: .regularExpression) != nil
        }
        if wrappers.count == 1, let current = wrappers.first { name = current }
    }
    var url = URLComponents()
    url.scheme = "swiftbar"
    url.host = "refreshplugin"
    url.queryItems = [URLQueryItem(name: "name", value: name)]
    guard let target = url.url else { return }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [target.absoluteString]
    try? open.run()
}
