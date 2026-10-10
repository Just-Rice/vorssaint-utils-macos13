// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// One still image of what a filter describes. macOS 14 has a call for it;
/// macOS 13 only has streams, so there a stream runs until its first whole
/// frame and that frame is the image.
enum ScreenCaptureCompat {
    static func captureImage(contentFilter: SCContentFilter,
                             configuration: SCStreamConfiguration) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: contentFilter,
                                                              configuration: configuration)
        }
        return try await SingleFrameCapture().image(filter: contentFilter, configuration: configuration)
    }

    /// The macOS 13 route on its own, so it can be exercised on any system.
    static func captureImageFromStream(contentFilter: SCContentFilter,
                                       configuration: SCStreamConfiguration) async throws -> CGImage {
        try await SingleFrameCapture().image(filter: contentFilter, configuration: configuration)
    }
}

private final class SingleFrameCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct TimedOut: Error {}

    private static let queue = DispatchQueue(label: "com.vorssaint.utils.single-frame-capture")
    private static let timeout: TimeInterval = 3

    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, Error>?

    func image(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: Self.queue)
        let result: Result<CGImage, Error>
        do {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                stream.startCapture { [weak self] error in
                    if let error { self?.finish(.failure(error)) }
                }
                Self.queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                    self?.finish(.failure(TimedOut()))
                }
            }
            result = .success(image)
        } catch {
            result = .failure(error)
        }
        try? await stream.stopCapture()
        return try result.get()
    }

    private func finish(_ result: Result<CGImage, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // Idle and blank frames carry no picture; only a complete one does.
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { finish(.success(image)) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(error))
    }
}
