//
//  ViewController.swift
//  ContainerMeasure
//
//  Created by @karthi on 26/08/22.
//

import UIKit
import AVFoundation
import AWSCore
import AWSRekognition

enum BoundingBox {
    case on
    case off
}

enum AWSConstants {
    
    static let CONGNITO_POOL_IDENTITY = "us-west-2:9888759e-0b99-4d1d-ad04-386350db4671"
    
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate{
    
  @IBOutlet weak var capturedImageView: UIImageView!
    
  @IBOutlet weak var cropView: UIView!
    
  @IBOutlet weak var boundingBoxSwitch: UISwitch!
    
  var cropRect = CGRect()
    
  // MARK: - Private Variables
  var captureSession : AVCaptureSession!
    
  var backCamera : AVCaptureDevice!
    
  var backInput : AVCaptureInput!
    
  var previewLayer : AVCaptureVideoPreviewLayer!

  var videoOutput : AVCaptureVideoDataOutput!
    
  var rekognitionClient: AWSRekognition?
    
  var boundingBox: BoundingBox = .off
    
  var takePicture = false

  // MARK: - Override Functions
  override func viewDidLoad() {
    super.viewDidLoad()
    self.awsSetup()
    self.offOnBox()
    self.cropView.layer.borderColor = UIColor.yellow.cgColor
    self.cropView.layer.borderWidth = 2
    self.capturedImageView.layer.borderWidth = 2
    self.capturedImageView.layer.borderColor = UIColor.white.cgColor
    self.capturedImageView.layer.cornerRadius = 10
    //self.cropRect = cropView.frame
    self.cropRect = CGRect(x: self.cropView.frame.origin.x, y: self.cropView.frame.origin.y - 100, width: 80, height: self.cropView.frame.height + 100)
  }
    
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    checkPermissions()
    self.setupAndStartCaptureSession()
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // TODO: Stop Session
    captureSession.stopRunning()
  }
    
   //MARK:- Actions
   @IBAction func captureImage(_ sender: UIButton?){
        takePicture = true
//        let pickerController = UIImagePickerController()
//        pickerController.delegate = self
//        pickerController.sourceType = .camera
//        pickerController.cameraCaptureMode = .photo
//        pickerController.cameraOverlayView = self.createOverlayView()
//        present(pickerController, animated: true)
   }
    
    @IBAction func switchAction(_ sender: UISwitch) {
        self.offOnBox()
    }
    
    func offOnBox() {
        if boundingBoxSwitch.isOn {
            self.cropView.isHidden = false
            self.boundingBox = .on
        } else {
            self.cropView.isHidden = true
            self.boundingBox = .off
        }
    }
    
    func createOverlayView() -> UIView {
        let view = UIView()
        view.frame = self.cropView.frame
        view.layer.borderColor = UIColor.yellow.cgColor
        view.layer.borderWidth = 2
        return view
    }
    
    @IBAction func galleryAction(_ sender: UIButton?){
        self.boundingBoxSwitch.setOn(false, animated: true)
        self.offOnBox()
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.sourceType = .savedPhotosAlbum
        present(pickerController, animated: true)
    }
    
    internal func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        dismiss(animated: true)
        
        guard let image = info[.originalImage] as? UIImage else {
            fatalError("couldn't load image from Photos")
        }
        guard let res = image.upOrientationImage() else {return}
        if boundingBox == .on {
            guard let appleCrop = self.cropImage(res, toRect: self.cropRect, viewWidth: self.view.frame.width, viewHeight: self.view.frame.height) else {return}
            self.capturedImageView.image = appleCrop
            self.sendImageToRekognition(image: appleCrop)
        } else {
            self.capturedImageView.image = res
            self.sendImageToRekognition(image: res)
        }
    }
}

extension ViewController {
  // MARK: - Camera
  private func checkPermissions() {
    // TODO: Checking permissions
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [self] granted in
        if !granted {
          self.showPermissionsAlert()
        }
      }
    case .denied, .restricted:
      showPermissionsAlert()
    default:
      return
    }
  }

  func setupAndStartCaptureSession(){
     DispatchQueue.global(qos: .userInitiated).async{
        //init session
        self.captureSession = AVCaptureSession()
        //start configuration
        self.captureSession.beginConfiguration()
        //session specific configuration
        if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
        }
        self.captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
        //setup inputs
        self.setupInputs()
        DispatchQueue.main.async {
                //setup preview layer
                self.setupPreviewLayer()
        }
        //setup output
        self.setupOutput()
        //commit configuration
        self.captureSession.commitConfiguration()
            //start running it
        self.captureSession.startRunning()
    }
  }
    
    func setupInputs(){
        //get back camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = device
        } else {
            //handle this appropriately for production purposes
            fatalError("no back camera")
        }
        //now we need to create an input objects from our devices
        guard let bInput = try? AVCaptureDeviceInput(device: backCamera) else {
            fatalError("could not create input device from back camera")
        }
        backInput = bInput
        if !captureSession.canAddInput(backInput) {
            fatalError("could not add back camera input to capture session")
        }
        //connect back camera input to session
        captureSession.addInput(backInput)
    }
    
    func setupOutput(){
        videoOutput = AVCaptureVideoDataOutput()
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            fatalError("could not add video output")
        }
        
        videoOutput.connections.first?.videoOrientation = .portrait
    }
    
    func setupPreviewLayer(){
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        previewLayer.frame = view.frame
        view.layer.insertSublayer(previewLayer, at: 0)
    }
}


// MARK: - AVCaptureDelegation
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      if takePicture {
          //try and get a CVImageBuffer out of the sample buffer
          guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
              return
          }
          //get a CIImage out of the CVImageBuffer
          let ciImage = CIImage(cvImageBuffer: cvBuffer)
          //get UIImage out of CIImage
          let uiImage = UIImage(ciImage: ciImage)
          guard let rotatedImage = uiImage.upOrientationImage() else {return}
          self.takePicture = false
          DispatchQueue.main.async {
              if self.boundingBox == .on {
                  guard let appleCrop1 = self.cropImage(rotatedImage, toRect: self.cropRect, viewWidth: self.view.frame.width, viewHeight: self.view.frame.height) else {return}
                  guard let appleCrop2 = self.cropImage(appleCrop1, toRect: self.cropRect, viewWidth: self.view.frame.width, viewHeight: self.view.frame.height) else {return}
                  self.capturedImageView.image = appleCrop2
                  self.sendImageToRekognition(image: appleCrop2)
              } else {
                  self.capturedImageView.image = rotatedImage
                  self.sendImageToRekognition(image: rotatedImage)
              }
          }
      }
  }
    
  //MARK: - AWS Methods
  func sendImageToRekognition(image: UIImage){
      if takePicture == false {
          let celebImageData = image.jpegData(compressionQuality: 0.2)
          let image = AWSRekognitionImage()
          image!.bytes = celebImageData
          guard let request = AWSRekognitionDetectTextRequest()
              else {
                  puts("Unable to initialize AWSRekognitionDetectLabelsRequest.")
                  return
          }
          request.image = image
          rekognitionClient?.detectText(request) {(res,err) in
              if err == nil {
                  guard let textDetctions = res?.textDetections else {return}
                  self.regExValidations(textDetctions)
              }
          }
      }
   }
    
    func regExValidations(_ textDetctions:[AWSRekognitionTextDetection]) {
        let confidenceDetection = textDetctions.filter({$0.types.rawValue == 1})
        let strArray = confidenceDetection.compactMap({$0.detectedText})
        let resStr = strArray.joined(separator: "-")
        DispatchQueue.main.async {
            self.showAlert(withTitle: "Detected Text", message: resStr)
        }
    }
    
    func awsSetup() {
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                                identityPoolId:AWSConstants.CONGNITO_POOL_IDENTITY)
        let configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        self.rekognitionClient = AWSRekognition.default()
    }

}


// MARK: - Helper
extension ViewController {

  private func showAlert(withTitle title: String, message: String) {
    DispatchQueue.main.async {
      let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: "Okay", style: .default))
      self.present(alertController, animated: true)
    }
  }

  private func showPermissionsAlert() {
    showAlert(
      withTitle: "Camera Permissions",
      message: "Please open Settings and grant permission for this app to use your camera.")
  }
  
  func cropImage(_ inputImage: UIImage, toRect cropRect: CGRect, viewWidth: CGFloat, viewHeight: CGFloat) -> UIImage?
    {
        let imageViewScale = max(inputImage.size.width / viewWidth,
                                 inputImage.size.height / viewHeight)

        // Scale cropRect to handle images larger than shown-on-screen size
        let cropZone = CGRect(x:cropRect.origin.x * imageViewScale,
                              y:cropRect.origin.y * imageViewScale,
                              width:cropRect.size.width * imageViewScale,
                              height:cropRect.size.height * imageViewScale)

        // Perform cropping in Core Graphics
        if let cutImageRef: CGImage = inputImage.cgImage?.cropping(to:cropZone) {
            // Return image to UIImage
            let croppedImage: UIImage = UIImage(cgImage: cutImageRef)
            return croppedImage
        } else {
            guard let ciImage = inputImage.ciImage else {return nil}
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {return nil}
            let croppedImage: UIImage = UIImage(cgImage: cgImage)
            return croppedImage
        }
   }
}


extension UIImage {
    func upOrientationImage() -> UIImage? {
        switch imageOrientation {
        case .up:
            return self
        default:
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            draw(in: CGRect(origin: .zero, size: size))
            let result = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return result
        }
    }
}
