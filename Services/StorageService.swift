import Foundation

/// Errors thrown by storage / repository operations.
enum StorageError: Error {
    case notFound
    case saveFailed(String)
    case invalidState(String)
}
