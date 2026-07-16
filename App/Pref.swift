import Combine
import MudPreferences

/// Bridges a single `MudPreferences` value onto an `ObservableObject`, reading
/// and writing it live (no cached copy on the enclosing object) and firing the
/// object's `objectWillChange` on set.
///
/// It mirrors Swift's own `@Published` "enclosing instance" subscript so that a
/// wrapped property's key path stays a `ReferenceWritableKeyPath` — that is
/// what keeps `$object.property` two-way bindings working. Because `@Pref` is
/// not `@Published`, the compiler's synthesized change notification does not
/// cover it, so the setter sends `objectWillChange` itself, before the write,
/// matching `@Published`'s `willSet` timing.
///
/// Live reads mean the enclosing `AppState` holds no cached value: a read goes
/// straight to `MudPreferences.shared`, and an external change only has to fire
/// one `objectWillChange.send()` for every view to re-read the fresh value.
@propertyWrapper
struct Pref<Value> {
    private let get: () -> Value
    private let set: (Value) -> Void

    /// The common case: a plain `MudPreferences` property.
    init(_ keyPath: WritableKeyPath<MudPreferences, Value>) {
        self.get = { MudPreferences.shared[keyPath: keyPath] }
        self.set = { newValue in
            // `MudPreferences.shared` is a `let`, and its setters are
            // `nonmutating` (they write through a shared reference-typed
            // `State`), so a key-path assignment needs a mutable local base.
            // The copy shares that same `State`, so the write reaches the store;
            // the key-path write-back into `prefs` is a harmless no-op.
            var prefs = MudPreferences.shared
            prefs[keyPath: keyPath] = newValue
        }
    }

    /// The escape hatch: accessors that can't be a plain property, e.g. one
    /// whose default is a runtime value the store doesn't own
    /// (`enabledExtensions`).
    init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }

    // Required by the language, but never used: `@Pref` is only valid as a
    // member of an `ObservableObject`, where the subscript below runs instead.
    var wrappedValue: Value {
        get { fatalError("@Pref is only usable on an ObservableObject property") }
        set { fatalError("@Pref is only usable on an ObservableObject property") }
    }

    static subscript<Enclosing: ObservableObject>(
        _enclosingInstance instance: Enclosing,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Pref<Value>>
    ) -> Value where Enclosing.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { instance[keyPath: storageKeyPath].get() }
        set {
            instance.objectWillChange.send()
            instance[keyPath: storageKeyPath].set(newValue)
        }
    }
}
