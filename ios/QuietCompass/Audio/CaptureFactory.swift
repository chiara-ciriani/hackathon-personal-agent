import Foundation
import QuietCore

public enum CaptureFactory {
    /// A/B → FOA capture (AVCaptureSession), C → mono capture (AVAudioEngine).
    /// `classifierEnabled` attaches the optional SoundAnalysis classifier (the first thing to turn off).
    public static func makeSource(mode: CaptureMode, classifierEnabled: Bool) -> FeatureSource {
        let classifier = classifierEnabled ? SoundClassifier() : nil
        switch mode {
        case .spatialAR, .spatialZones:
            return FOAFeatureSource(classifier: classifier)
        case .arLevels:
            return MonoFeatureSource(classifier: classifier)
        }
    }
}
