import MCP

extension Value {
  var stringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    default:
      return nil
    }
  }

  var intValue: Int? {
    switch self {
    case .int(let value):
      return Int(value)
    case .double(let value):
      return Int(value)
    case .string(let value):
      return Int(value)
    default:
      return nil
    }
  }
}
