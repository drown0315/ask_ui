import AVFoundation
import CoreMediaIO
import Foundation
import VideoToolbox

struct IOSCaptureDevice {
    let id: String
    let name: String
    let model: String
    let manufacturer: String
    let device: AVCaptureDevice
}

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func enableIOSScreenCaptureDevices() {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        UInt32(MemoryLayout.size(ofValue: allow)),
        &allow
    )
    // CoreMediaIO publishes iOS screen devices asynchronously after opt-in.
    // A fixed settle matches the proven physical recorder helper behavior.
    Thread.sleep(forTimeInterval: 1.0)
}

func currentIOSDevices() -> [IOSCaptureDevice] {
    let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external, .builtInWideAngleCamera],
        mediaType: nil,
        position: .unspecified
    )
    return discovery.devices
        .filter { $0.modelID == "iOS Device" && $0.manufacturer == "Apple Inc." }
        .map {
            IOSCaptureDevice(
                id: $0.uniqueID,
                name: $0.localizedName,
                model: $0.modelID,
                manufacturer: $0.manufacturer,
                device: $0
            )
        }
}

func waitForCaptureDeviceEvents(until deadline: Date) {
    RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.25)))
}

func discoverIOSDevices(timeout: TimeInterval = 10) -> [IOSCaptureDevice] {
    enableIOSScreenCaptureDevices()
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let devices = currentIOSDevices()
        if !devices.isEmpty {
            return devices
        }
        waitForCaptureDeviceEvents(until: deadline)
    } while Date() < deadline
    return []
}

func resolveIOSDevice(
    id: String,
    name: String?,
    timeout: TimeInterval = 10
) throws -> IOSCaptureDevice? {
    enableIOSScreenCaptureDevices()
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let devices = currentIOSDevices()
        if let idMatch = devices.first(where: { $0.id == id }) {
            return idMatch
        }
        if let name {
            let nameMatches = devices.filter { $0.name == name }
            if nameMatches.count > 1 {
                throw CaptureError("capture_device_not_found: multiple capture devices matched name \(name); use a capture id")
            }
            if let nameMatch = nameMatches.first {
                return nameMatch
            }
        }
        waitForCaptureDeviceEvents(until: deadline)
    } while Date() < deadline
    return nil
}

final class CaptureStreamer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "ios-screen-mvp.capture")
    private let maxFPS: Int
    private let bitRate: Int
    private let deviceID: String
    private var encoder: VTCompressionSession?
    private var dimensions: (width: Int, height: Int)?
    private var stopping = false

    init(deviceID: String, maxFPS: Int, bitRate: Int) {
        self.deviceID = deviceID
        self.maxFPS = maxFPS
        self.bitRate = bitRate
    }

    func start(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError("capture_device_busy: cannot add capture input") }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError("capture_start_failed: cannot add video output") }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else { throw CaptureError("capture_start_failed: session did not start") }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, !self.stopping else { return }
            self.stopping = true
            self.output.setSampleBufferDelegate(nil, queue: nil)
            if let encoder = self.encoder {
                VTCompressionSessionCompleteFrames(encoder, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(encoder)
            }
            self.encoder = nil
            self.session.stopRunning()
            DispatchQueue.main.async { CFRunLoopStop(CFRunLoopGetMain()) }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !stopping, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            try ensureEncoder(for: imageBuffer)
            guard let encoder else { return }
            var flags = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(
                encoder,
                imageBuffer: imageBuffer,
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                duration: CMSampleBufferGetDuration(sampleBuffer),
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flags
            )
            guard status == noErr else { throw CaptureError("video_encode_failed: status \(status)") }
        } catch {
            eprint(String(describing: error))
            stop()
        }
    }

    private func ensureEncoder(for pixelBuffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        if dimensions == nil {
            dimensions = (width, height)
            try createEncoder(width: width, height: height)
            writeMetadata(width: width, height: height)
        } else if dimensions!.width != width || dimensions!.height != height {
            if let encoder {
                VTCompressionSessionCompleteFrames(encoder, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(encoder)
            }
            dimensions = (width, height)
            try createEncoder(width: width, height: height)
            writeMetadata(width: width, height: height)
        }
    }

    private func createEncoder(width: Int, height: Int) throws {
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw CaptureError("video_encode_failed: cannot create encoder (\(status))") }
        encoder = created
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: maxFPS as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxFPS as CFNumber)
        let limit = [bitRate / 8, 1] as CFArray
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_DataRateLimits, value: limit)
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(created)
        guard prepareStatus == noErr else { throw CaptureError("video_encode_failed: cannot prepare encoder (\(prepareStatus))") }
    }

    fileprivate func writeEncoded(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil
        var accessUnit = Data()
        var hasConfiguration = false

        if isKeyFrame, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                var count = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: &count,
                    nalUnitHeaderLengthOut: nil
                )
                if status == noErr, let pointer {
                    accessUnit.append(contentsOf: [0, 0, 0, 1])
                    accessUnit.append(pointer, count: size)
                    hasConfiguration = true
                }
            }
        }

        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        ) == kCMBlockBufferNoErr, let dataPointer else { return }

        var offset = 0
        while offset + 4 <= totalLength {
            let bytes = UnsafeRawPointer(dataPointer + offset).assumingMemoryBound(to: UInt8.self)
            let nalLength = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            offset += 4
            guard nalLength >= 0, offset + nalLength <= totalLength else { return }
            accessUnit.append(contentsOf: [0, 0, 0, 1])
            accessUnit.append(UnsafeRawPointer(dataPointer + offset).assumingMemoryBound(to: UInt8.self), count: nalLength)
            offset += nalLength
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let micros = max(0, Int64(CMTimeGetSeconds(timestamp) * 1_000_000))
        var flags: UInt8 = isKeyFrame ? 0x01 : 0
        if hasConfiguration { flags |= 0x02 }
        writeFrame(payload: accessUnit, flags: flags, ptsMicros: UInt64(micros))
    }

    private func writeMetadata(width: Int, height: Int) {
        let pixelRatio = 3.0
        let metadata: [String: Any] = [
            "type": "ready",
            "deviceId": deviceID,
            "screenWidth": width,
            "screenHeight": height,
            "logicalWidth": Double(width) / pixelRatio,
            "logicalHeight": Double(height) / pixelRatio,
            "devicePixelRatio": pixelRatio,
            "videoCodec": "h264",
            "controlBackend": "flutterRuntime"
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: metadata) else { return }
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private func writeFrame(payload: Data, flags: UInt8, ptsMicros: UInt64) {
        var length = UInt32(payload.count).bigEndian
        var timestamp = ptsMicros.bigEndian
        var header = Data(bytes: &length, count: 4)
        header.append(flags)
        header.append(Data(bytes: &timestamp, count: 8))
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(payload)
    }
}

private let compressionOutputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard status == noErr, let refcon, let sampleBuffer else {
        eprint("video_encode_failed: compression callback status \(status)")
        return
    }
    Unmanaged<CaptureStreamer>.fromOpaque(refcon).takeUnretainedValue().writeEncoded(sampleBuffer)
}

struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func usage() -> Never {
    eprint("Usage: ios_capture list | stream --device-id ID [--max-fps 30] [--bit-rate 6000000]")
    exit(2)
}

@main
enum IOSCaptureMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { usage() }
        if command == "list" {
            print("id\tname\tmodel\tmanufacturer")
            for item in discoverIOSDevices() {
                print("\(item.id)\t\(item.name)\t\(item.model)\t\(item.manufacturer)")
            }
            return
        }
        guard command == "stream",
              let deviceID = value(after: "--device-id", in: arguments),
              let maxFPS = Int(value(after: "--max-fps", in: arguments) ?? "30"),
              let bitRate = Int(value(after: "--bit-rate", in: arguments) ?? "6000000")
        else { usage() }

        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            eprint("capture_permission_denied: camera permission denied")
            exit(3)
        }
        let deviceName = value(after: "--device-name", in: arguments)
        let device: IOSCaptureDevice
        do {
            guard let resolved = try resolveIOSDevice(id: deviceID, name: deviceName) else {
                eprint("capture_device_not_found: no trusted physical iOS capture device matched id \(deviceID) or name \(deviceName ?? "<none>")")
                exit(4)
            }
            device = resolved
        } catch {
            eprint(String(describing: error))
            exit(4)
        }

        let streamer = CaptureStreamer(deviceID: deviceID, maxFPS: maxFPS, bitRate: bitRate)
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        term.setEventHandler { streamer.stop() }
        interrupt.setEventHandler { streamer.stop() }
        term.resume()
        interrupt.resume()
        do {
            try streamer.start(device: device.device)
            RunLoop.main.run()
        } catch {
            eprint(String(describing: error))
            exit(6)
        }
    }
}
