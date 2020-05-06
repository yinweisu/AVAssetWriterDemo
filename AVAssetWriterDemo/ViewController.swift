//
//  ViewController.swift
//  AVAssetWriterDemo
//
//  Created by Weisu Yin on 5/6/20.
//  Copyright © 2020 UCDavis. All rights reserved.

import UIKit
import AVFoundation
import AVKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var recordButton: UIButton!
    var recording = false {
        didSet {
            recording ? self.start() : self.stop()
        }
    }
    
    let captureSession = AVCaptureSession()
    lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    
    var videoDataOutput: AVCaptureVideoDataOutput?
    var assetWriter: AVAssetWriter?
    var assetWriterInput: AVAssetWriterInput?
    var filePath: URL?
    var sessionAtSourceTime: CMTime?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.recording = false
        self.requestCameraPermission()
    }
    
    @IBAction func recordButtonPressed(_ sender: Any) {
        recording.toggle()
    }
    
    @IBAction func playRecordedVideo(_ sender: Any) {
        guard let url = filePath else {
            print("Can't get video url")
            return
        }
         let player = AVPlayer(url: url)
         let playerController = AVPlayerViewController()
         playerController.player = player
         present(playerController, animated: true) {
             player.play()
         }
    }
    func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setupCaptureSession()
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupCaptureSession()
                    }
                }
            }
            
        case .denied:
            return
            
        case .restricted:
            return
        @unknown default:
            fatalError()
        }
    }
    
    func setupCaptureSession() {
        self.captureSession.beginConfiguration()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoCaptureDevice), self.captureSession.canAddInput(videoDeviceInput)
            else { return }
        self.captureSession.addInput(videoDeviceInput)
        
        let tempVideoDataOutput = AVCaptureVideoDataOutput()
        tempVideoDataOutput.alwaysDiscardsLateVideoFrames = true
        tempVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        tempVideoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        self.captureSession.addOutput(tempVideoDataOutput)
        
        self.captureSession.commitConfiguration()
        self.captureSession.startRunning()
        
        self.videoDataOutput = tempVideoDataOutput
        self.previewLayer.frame = self.previewView.frame
        self.previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.view.layer.addSublayer(previewLayer)
    }
    
     // This mothod will overwrite previous video files
    func videoFileLocation() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mov")
        do {
        if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
            try FileManager.default.removeItem(at: videoOutputUrl)
            print("file removed")
        }
        } catch {
            print(error)
        }

        return videoOutputUrl
    }
    
    func setUpWriter() {
        do {
            filePath = videoFileLocation()
            assetWriter = try AVAssetWriter(outputURL: filePath!, fileType: AVFileType.mov)

            // add video input
            let settings = self.videoDataOutput?.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : 720,
            AVVideoHeightKey : 1280,
            AVVideoCompressionPropertiesKey : [
                AVVideoAverageBitRateKey : 2300000,
                ],
            ])
            guard let assetWriterInput = assetWriterInput, let assetWriter = assetWriter else { return }
            assetWriterInput.expectsMediaDataInRealTime = true
//            assetWriterInput.transform = CGAffineTransform(rotationAngle: .pi/2) // Adapt to portrait mode
            
            if assetWriter.canAdd(assetWriterInput) {
                assetWriter.add(assetWriterInput)
                print("asset input added")
            } else {
                print("no input added")
            }

            assetWriter.startWriting()
            
            self.assetWriter = assetWriter
            self.assetWriterInput = assetWriterInput
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }

    func canWrite() -> Bool {
        return recording && assetWriter != nil && assetWriter?.status == .writing
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = .portrait
        guard self.recording else { return }
        
        let writable = self.canWrite()

        if writable, self.sessionAtSourceTime == nil {
            // start writing
            sessionAtSourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
            self.assetWriter?.startSession(atSourceTime: sessionAtSourceTime!)
        }
        guard let assetWriterInput = self.assetWriterInput else { return }
        if writable, assetWriterInput.isReadyForMoreMediaData {
            // write video buffer
            assetWriterInput.append(sampleBuffer)
        }

    }

    func start() {
        self.recordButton.setTitle("Stop", for: .normal)
        self.sessionAtSourceTime = nil
        self.setUpWriter()
        switch self.assetWriter?.status {
        case .writing:
            print("status writing")
        case .failed:
            print("status failed")
        case .cancelled:
            print("status cancelled")
        case .unknown:
            print("status unknown")
        default:
            print("status completed")
        }

    }

    func stop() {
        self.recordButton.setTitle("Record", for: .normal)
        self.assetWriterInput?.markAsFinished()
        print("marked as finished")
        self.assetWriter?.finishWriting { [weak self] in
            self?.sessionAtSourceTime = nil
        }
        print("finished writing \(self.filePath)")
    }

}
