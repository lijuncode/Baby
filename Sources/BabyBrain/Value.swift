
/*
 * @nixzhu (zhuhongxu@gmail.com)
 */

import Foundation

public enum Value {
  case empty
  indirect case null(optionalValue: Value?)
  case bool(value: Bool)
  public enum Number {
    case int(Int)
    case double(Double)
  }
  case number(value: Number)
  case string(value: String)
  indirect case object(name: String, dictionary: [String: Value], keys: [String])
  indirect case array(name: String, values: [Value])
  // hyper types
  case url(value: URL)
  public enum DateType {
    case iso8601
    case dateOnly
    case secondsSince1970
  }
  case date(type: DateType)
}

extension Value {
  private static func mergedValue(of values: [Value]) -> Value {
    if let first = values.first {
      return values.dropFirst().reduce(first, { $0.merge($1) })
    } else {
      return .empty
    }
  }

  private func merge(_ other: Value) -> Value {
    switch (self, other) {
    case (.empty, .empty):
      return .empty
    case (.empty, let valueB):
      return valueB
    case (let valueA, .empty):
      return valueA
    case (let .null(optionalValueA), let .null(optionalValueB)):
      switch (optionalValueA, optionalValueB) {
      case (.some(let a), .some(let b)):
        return .null(optionalValue: a.merge(b))
      case (.some(let a), .none):
        return .null(optionalValue: a)
      case (.none, .some(let b)):
        return .null(optionalValue: b)
      case (.none, .none):
        return .null(optionalValue: nil)
      }
    case (let .null(optionalValue), let valueB):
      if let valueA = optionalValue {
        return .null(optionalValue: .some(valueA.merge(valueB)))
      } else {
        return .null(optionalValue: .some(valueB))
      }
    case (let valueA, let .null(optionalValue)):
      if let valueB = optionalValue {
        return .null(optionalValue: .some(valueB.merge(valueA)))
      } else {
        return .null(optionalValue: .some(valueA))
      }
    case (let .bool(valueA), let .bool(valueB)):
      return .bool(value: valueA && valueB)
    case (let .number(valueA), let .number(valueB)):
      var newValue = valueA
      if case .double(_) = valueB {
        newValue = valueB
      }
      return .number(value: newValue)
    case (let .string(valueA), let .string(valueB)):
      let value = valueA.isEmpty ? valueB : valueA
      return .string(value: value)
    case (let .object(nameA, dictionaryA, keysA), let .object(nameB, dictionaryB, keysB)):
      guard nameA == nameB else { fatalError("Unsupported object merge!") }
      var dictionary = dictionaryA
      for key in keysA {
        let valueA = dictionaryA[key]!
        if let valueB = dictionaryB[key] {
          dictionary[key] = valueA.merge(valueB)
        } else {
          dictionary[key] = valueA.isNull ? valueA : .null(optionalValue: valueA)
        }
      }
      for key in keysB {
        let valueB = dictionaryB[key]!
        if let valueA = dictionaryA[key] {
          dictionary[key] = valueB.merge(valueA)
        } else {
          dictionary[key] = valueB.isNull ? valueB : .null(optionalValue: valueB)
        }
      }
      var keys = keysA
      for key in keysB {
        if !keys.contains(key) {
          keys.append(key)
        }
      }
      return .object(name: nameA, dictionary: dictionary, keys: keys)
    case (let .array(nameA, valuesA), let .array(nameB, valuesB)):
      guard nameA == nameB else { fatalError("Unsupported array merge!") }
      let value = Value.mergedValue(of: valuesA + valuesB)
      return .array(name: nameA, values: [value])
    case (let .url(valueA), .url):
      return .url(value: valueA)
    case (let .date(typeA), .date):
      return .date(type: typeA)
    case (.url, let .string(value)):
      return .string(value: value)
    case (let .string(value), .url):
      return .string(value: value)
    default:
      fatalError("Unsupported merge! \(self), \(other)")
    }
  }

  public func upgraded(newName: String, arrayObjectMap: [String: String] ) -> Value {
    switch self {
    case let .number(value):
      switch value {
      case .int(let int):
        if let dateType = int.dateType {
          return .date(type: dateType)
        } else {
          return self
        }
      case .double(let double):
        if let dateType = double.dateType {
          return .date(type: dateType)
        } else {
          return self
        }
      }
    case let .string(value):
      if let url = URL(string: value), url.host != nil { // TODO: better url detect
        return .url(value: url)
      } else if let dateType = value.dateType {
        return .date(type: dateType)
      } else {
        return self
      }
    case let .object(_, dictionary, keys):
      var newDictionary: [String: Value] = [:]
      dictionary.forEach { newDictionary[$0] = $1.upgraded(newName: $0, arrayObjectMap: arrayObjectMap) }
      return .object(name: newName, dictionary: newDictionary, keys: keys)
    case let .array(_, values):
      let newValues = values.map { $0.upgraded(newName: newName.singularForm(arrayObjectMap: arrayObjectMap), arrayObjectMap: arrayObjectMap) }
      let value = Value.mergedValue(of: newValues)
      return .array(name: newName, values: [value])
    default:
      return self
    }
  }
}

extension Value {
  public var type: String {
    switch self {
    case .empty:
      return "Any"
    case let .null(optionalValue):
      if let value = optionalValue {
        return value.type + "?"
      } else {
        return "Any?"
      }
    case .bool:
      return "Bool"
    case let .number(value):
      switch value {
      case .int:
        return "Int"
      case .double:
        return "Double"
      }
    case .string:
      return "String"
    case let .object(name, _, _):
      return name.type
    case let .array(_, values):
      if let value = values.first {
        return "[" + value.type + "]"
      } else {
        return "[Any]"
      }
    case .url:
      return "URL"
    case .date:
      return "Date"
    }
  }
}

extension Value {
  var isNull: Bool {
    switch self {
    case .null:
      return true
    default:
      return false
    }
  }
}

extension String {
  public func singularForm(meta: Meta) -> String {
    return singularForm(arrayObjectMap: meta.arrayObjectMap)
  }
  public func singularForm(arrayObjectMap: [String: String]) -> String { // TODO: better singularForm
    if let name = arrayObjectMap[self] {
      return name
    } else {
      if hasSuffix("list") {
        return String(characters.dropLast(4))
      } else if hasSuffix("s") {
        return String(characters.dropLast())
      } else {
        return self
      }
    }
  }

  public var type: String { // TODO: better type
    return self.components(separatedBy: "_").map({ $0.capitalizingFirstLetter() }).joined().capitalizingFirstLetter()
  }

  public func propertyName(meta: Meta) -> String {
    if let propertyName = meta.propertyMap[self] {
      return propertyName
    } else {
      return type.lowercasingFirstLetter()
    }
  }

  func capitalizingFirstLetter() -> String {
    if let first = characters.first {
      return String(first).uppercased() + String(characters.dropFirst())
    } else {
      return self
    }
  }

  func lowercasingFirstLetter() -> String {
    if let first = characters.first {
      return String(first).lowercased() + String(characters.dropFirst())
    } else {
      return self
    }
  }
}

extension DateFormatter {
  static let iso8601: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(abbreviation: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
    return formatter
  }()

  static let dateOnly: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

extension String {
  var dateType: Value.DateType? {
    if DateFormatter.iso8601.date(from: self) != nil {
      return .iso8601
    }
    if DateFormatter.dateOnly.date(from: self) != nil {
      return .dateOnly
    }
    return nil
  }
}

extension Int {
  var dateType: Value.DateType? {
    if self >= 1000000000 {
      return .secondsSince1970
    }
    return nil
  }
}

extension Double {
  var dateType: Value.DateType? {
    if self >= 1000000000 {
      return .secondsSince1970
    }
    return nil
  }
}

