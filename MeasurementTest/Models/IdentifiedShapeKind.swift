#if os(iOS)
import Foundation

enum IdentifiedShapeKind: String {
    case triangle
    case rectangle

    var title: String {
        rawValue.capitalized
    }
}
#endif
