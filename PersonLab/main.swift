// Copyright 2020 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArgumentParser
import Foundation
import ModelSupport
import SwiftCV
import TensorFlow

struct Inference: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "personlab",
    abstract: """
      Runs human pose estimation on a local image file or on a local webcam.
      """
  )

  @Argument(help: "Path to checkpoint directory")
  var checkpointPath: String

  @Option(name: .shortAndLong, help: "Path to local image to run pose estimation on")
  var imagePath: String?

  @Flag(name: .shortAndLong, help: "Run local webcam demo")
  var webcamDemo: Bool

  @Flag(name: .shortAndLong, help: "Print profiling data")
  var profiling: Bool

  func run() {
    Context.local.learningPhase = .inference
    let config = Config(checkpointPath: checkpointPath, printProfilingData: profiling)
    let model = PersonLab(config)

    if let imagePath = imagePath {
      let fileManager = FileManager()
      if !fileManager.fileExists(atPath: imagePath) {
        print("No image found at path: \(imagePath)")
        return
      }
      let swiftcvImage = imread(imagePath)
      let image = Image(tensor: Tensor<UInt8>(cvMat: swiftcvImage)!)

      var poses = [Pose]()
      if profiling {
        print("Running model 10 times to see how inference time improves.")
        for _ in 1...10 {
          poses = model(image)
        }
      } else {
        poses = model(image)
      }

      for pose in poses {
        draw(pose, on: swiftcvImage, color: config.color, lineWidth: config.lineWidth)
      }
      ImShow(image: swiftcvImage)
      WaitKey(delay: 0)
    }

    if webcamDemo {
      let videoCaptureDevice = VideoCapture(0)
      videoCaptureDevice.set(VideoCaptureProperties.CAP_PROP_BUFFERSIZE, 1)  // Reduces latency

      let frame = Mat()
      while true {
        videoCaptureDevice.read(into: frame)
        let image = Image(tensor: Tensor<UInt8>(cvMat: frame)!)
        let poses = model(image)

        for pose in poses {
          draw(pose, on: frame, color: config.color, lineWidth: config.lineWidth)
        }
        ImShow(image: frame)
        WaitKey(delay: 1)
      }
    }
  }
}

Inference.main()
