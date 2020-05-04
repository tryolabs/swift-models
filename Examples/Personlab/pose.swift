import TensorFlow

struct CPUTensor<T: TensorFlowScalar> {
  private var flattenedTensor: [T]
  var shape: TensorShape

  init(_ tensor: Tensor<T>) {
    self.flattenedTensor = tensor.scalars
    self.shape = tensor.shape
  }

  subscript(indexes: Int...) -> T {
    var oneDimensionalIndex = 0
    for i in 1..<shape.count {
      oneDimensionalIndex += indexes[i - 1] * shape[i...].reduce(1, *)
    }
    // Last dimension doesn't have multipliers.
    oneDimensionalIndex += indexes.last!
    return flattenedTensor[oneDimensionalIndex]
  }
}

struct Keypoint {
  var y: Float
  var x: Float
  let index: KeypointIndex
  let score: Float

  init(heatmapY: Int, heatmapX: Int, index: Int, score: Float, offsets: CPUTensor<Float>) {
    self.y = Float(heatmapY) * Float(config.outputStride) + offsets[heatmapY, heatmapX, index]
    self.x = Float(heatmapX) * Float(config.outputStride) + offsets[heatmapY, heatmapX, index + KeypointIndex.allCases.count]
    self.index = KeypointIndex(rawValue: index)!
    self.score = score
  }

  init(y: Float, x: Float, index: KeypointIndex, score: Float) {
    self.y = y
    self.x = x
    self.index = index
    self.score = score
  }

  func isWithinRadiusOfCorrespondingPoint(in poses: [Pose], radius: Float = config.nmsRadius) -> Bool {
    return poses.contains { pose in
      let correspondingKeypoint = pose.getKeypoint(self.index)!
      let dy = correspondingKeypoint.y - self.y
      let dx = correspondingKeypoint.x - self.x
      let squaredDistance = dy * dy + dx * dx
      return squaredDistance <= radius * radius
    }
  }
}

enum KeypointIndex: Int, CaseIterable {
  case nose = 0
  case leftEye
  case rightEye
  case leftEar
  case rightEar
  case leftShoulder
  case rightShoulder
  case leftElbow
  case rightElbow
  case leftWrist
  case rightWrist
  case leftHip
  case rightHip
  case leftKnee
  case rightKnee
  case leftAnkle
  case rightAnkle
}

enum Direction { case fwd, bwd }

func getNextKeypointIndexAndDirection(_ keypointId: KeypointIndex) -> [(KeypointIndex, Direction)] {
  switch keypointId {
  case .nose: return [(.leftEye, .fwd), (.rightEye, .fwd), (.leftShoulder, .fwd), (.rightShoulder, .fwd)]
  case .leftEye: return [(.nose, .bwd), (.leftEar, .fwd)]
  case .rightEye: return [(.nose, .bwd), (.rightEar, .fwd)]
  case .leftEar: return [(.leftEye, .bwd)]
  case .rightEar: return [(.rightEye, .bwd)]
  case .leftShoulder: return [(.leftHip, .fwd), (.leftElbow, .fwd), (.nose, .bwd)]
  case .rightShoulder: return [(.rightHip, .fwd), (.rightElbow, .fwd), (.nose, .bwd)]
  case .leftElbow: return [(.leftWrist, .fwd), (.leftShoulder, .bwd)]
  case .rightElbow: return [(.rightWrist, .fwd), (.rightShoulder, .bwd)]
  case .leftWrist: return [(.leftElbow, .bwd)]
  case .rightWrist: return [(.rightElbow, .bwd)]
  case .leftHip: return [(.leftKnee, .fwd), (.leftShoulder, .bwd)]
  case .rightHip: return [(.rightKnee, .fwd), (.rightShoulder, .bwd)]
  case .leftKnee: return [(.leftAnkle, .fwd), (.leftHip, .bwd)]
  case .rightKnee: return [(.rightAnkle, .fwd), (.rightHip, .bwd)]
  case .leftAnkle: return [(.leftKnee, .bwd)]
  case .rightAnkle: return [(.rightKnee, .bwd)]
  }
}

/// Maps a pair of keypoint indexes to the appropiate index to be used
/// in the displacement forward and backward tensors.
let keypointPairToDisplacementIndexMap: [Set<KeypointIndex>: Int] = [
  Set([.nose, .leftEye]): 0,
  Set([.leftEye, .leftEar]): 1,
  Set([.nose, .rightEye]): 2,
  Set([.rightEye, .rightEar]): 3,
  Set([.nose, .leftShoulder]): 4,
  Set([.leftShoulder, .leftElbow]): 5,
  Set([.leftElbow, .leftWrist]): 6,
  Set([.leftShoulder, .leftHip]): 7,
  Set([.leftHip, .leftKnee]): 8,
  Set([.leftKnee, .leftAnkle]): 9,
  Set([.nose, .rightShoulder]): 10,
  Set([.rightShoulder, .rightElbow]): 11,
  Set([.rightElbow, .rightWrist]): 12,
  Set([.rightShoulder, .rightHip]): 13,
  Set([.rightHip, .rightKnee]): 14,
  Set([.rightKnee, .rightAnkle]): 15
]

struct Pose  {
  var keypoints: [Keypoint?] = Array(repeating: nil, count: KeypointIndex.allCases.count)
  var resolution = config.inputImageSize

  mutating func add(_ keypoint: Keypoint) {
    keypoints[keypoint.index.rawValue] = keypoint
  }

  func getKeypoint(_ index: KeypointIndex) -> Keypoint? {
    return keypoints[index.rawValue]
  }

  mutating func rescale(to newResolution: (height: Int, width: Int)) {
    for i in 0..<keypoints.count {
      if var k = keypoints[i] {
        k.y *= Float(newResolution.height) / Float(resolution.height)
        k.x *= Float(newResolution.width) / Float(resolution.width)
        self.keypoints[i] = k
      }
    }
    self.resolution = newResolution
  }
}

extension Pose: CustomStringConvertible {
  var description: String {
    var description = ""
    for keypoint in keypoints {
      description.append("\(keypoint!.index) - \(keypoint!.score) | \(keypoint!.y) - \(keypoint!.x)\n")
    }
    return description
  }
}
