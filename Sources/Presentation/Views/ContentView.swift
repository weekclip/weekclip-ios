import SwiftUI

public struct ContentView: View {
  @State private var title = "WeekClip iOS"

  public init() {}

  public var body: some View {
    VStack {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundStyle(.tint)
      Text(title)
        .font(.largeTitle)
        .fontWeight(.bold)
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
