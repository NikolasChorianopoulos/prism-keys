import SwiftUI

/// Drop-in for `@State` that doesn't need the SwiftUI macro plugin (which only ships
/// with full Xcode). Lets the app build with just the Command Line Tools.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private var storage: State<Value>
    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { storage.projectedValue }
}
