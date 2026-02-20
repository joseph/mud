import Foundation

/// Defer a state mutation out of the current SwiftUI view-update cycle.
///
/// SwiftUI event handlers (`onKeyPress`, `onChange`, `updateNSView`, etc.)
/// run during the view-update pipeline. Setting `@Published` properties
/// inside them triggers "Publishing changes from within view updates."
/// Wrapping the mutation in `deferMutation` moves it to the next run-loop
/// iteration, avoiding the warning and undefined behavior.
/// 
func deferMutation(_ work: @escaping () -> Void) {
    DispatchQueue.main.async(execute: work)
}
