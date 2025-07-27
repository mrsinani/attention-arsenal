import Foundation
import os.log

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.attentionarsenal", category: "Performance")
    
    private init() {}
    
    func measureOperation<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try await operation()
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = (endTime - startTime) * 1000 // Convert to milliseconds
            
            logger.info("⏱️ \(name) completed in \(String(format: "%.2f", duration))ms")
            return result
        } catch {
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = (endTime - startTime) * 1000
            
            logger.error("❌ \(name) failed after \(String(format: "%.2f", duration))ms: \(error.localizedDescription)")
            throw error
        }
    }
    
    func measureSyncOperation<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try operation()
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = (endTime - startTime) * 1000
            
            logger.info("⏱️ \(name) completed in \(String(format: "%.2f", duration))ms")
            return result
        } catch {
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = (endTime - startTime) * 1000
            
            logger.error("❌ \(name) failed after \(String(format: "%.2f", duration))ms: \(error.localizedDescription)")
            throw error
        }
    }
    
    func logInfo(_ message: String) {
        logger.info("ℹ️ \(message)")
    }
    
    func logWarning(_ message: String) {
        logger.warning("⚠️ \(message)")
    }
    
    func logError(_ message: String) {
        logger.error("❌ \(message)")
    }
} 