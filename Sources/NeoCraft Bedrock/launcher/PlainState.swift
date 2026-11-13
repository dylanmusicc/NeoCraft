import SwiftUI

/// SwiftUI's `State` property wrapper. In the macOS 27 SDK `@State` resolves to a macro whose plugin
/// ships only with Xcode, so a build with the Command Line Tools uses the wrapper through this name.
typealias PlainState<Value> = SwiftUI.State<Value>
