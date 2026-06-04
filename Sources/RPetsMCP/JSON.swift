import Foundation

// MARK: - JSON Value

indirect enum JSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let d) = self else { return nil }
        return d[key]
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var boolValue: Bool? {
        guard case .bool(let b) = self else { return nil }
        return b
    }
}

// MARK: - JSON-RPC ID

enum JSONRPCId: Codable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid JSON-RPC id")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):    try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

// MARK: - JSON-RPC message (request or notification)

struct JSONRPCMessage: Decodable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: JSONValue?
}

// MARK: - JSON-RPC response

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCId?
    let result: JSONValue?
    let error: JSONRPCErrorBody?

    init(id: JSONRPCId?, result: JSONValue) {
        self.id = id; self.result = result; self.error = nil
    }

    init(id: JSONRPCId?, error: JSONRPCErrorBody) {
        self.id = id; self.result = nil; self.error = error
    }
}

struct JSONRPCErrorBody: Encodable {
    let code: Int
    let message: String
}
