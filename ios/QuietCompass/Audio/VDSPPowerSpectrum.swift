// PowerSpectrumComputing backed by Accelerate (vDSP split-complex real FFT).
import Accelerate
import QuietCore

public final class VDSPPowerSpectrum: PowerSpectrumComputing, @unchecked Sendable {
    // @unchecked: setup is immutable after init; each instance must be used from one queue at a time
    // (the scratch buffers below are reused).
    public let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var real: [Float]
    private var imag: [Float]

    public init(size: Int = OctaveBands.fftSize) {
        precondition(size & (size - 1) == 0)
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// |X[k]|², k = 0…N/2, unscaled (same convention as QuietCore.FFT).
    public func powerSpectrum(of windowed: [Float]) -> [Double] {
        precondition(windowed.count == size)
        let half = size / 2
        var out = [Double](repeating: 0, count: half + 1)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // vDSP's real FFT output is scaled by 2 relative to the DFT; packed: imagp[0] holds Nyquist.
                let dc = Double(rp[0]) / 2, ny = Double(ip[0]) / 2
                out[0] = dc * dc
                out[half] = ny * ny
                for k in 1..<half {
                    let r = Double(rp[k]) / 2, i = Double(ip[k]) / 2
                    out[k] = r * r + i * i
                }
            }
        }
        return out
    }
}
