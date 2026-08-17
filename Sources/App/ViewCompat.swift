import AppKit
import SwiftUI

/// The bundled mosque logo, rounded like an app icon.
///
/// Falls back to an SF Symbol if `logo.png` is missing from the bundle so the UI
/// never renders an empty box.
struct AppLogo: View {
    let size: CGFloat

    var body: some View {
        if let image = NSImage(named: "logo") ?? bundledLogo {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        } else {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: size * 0.6))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
        }
    }

    private var bundledLogo: NSImage? {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

extension View {
    /// `onChange` that works on macOS 13 without tripping the macOS 14
    /// deprecation of the single-parameter overload.
    ///
    /// The deployment target is Ventura so mySolat still runs on 2017-era Intel
    /// Macs; this keeps the call sites clean on both SDKs.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V,
                                     perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}
