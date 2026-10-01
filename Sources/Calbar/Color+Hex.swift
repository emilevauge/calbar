import SwiftUI
import CalbarCore

extension Color {
    init(hex: String) {
        if let rgb = RGB(hex: hex) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } else {
            self = .accentColor
        }
    }
}
