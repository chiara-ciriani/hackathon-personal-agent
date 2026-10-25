import Foundation
struct AgentConnectionError: LocalizedError {
 let errorDescription: String?
 init(_ message:String){errorDescription=message}
}
let accumulator = CommunityAccumulator()
for i in 0...300 { accumulator.add(level: -40, peak: -20, samples: 4800, rate: 48000, channels: 1, time: Double(i)/10) }
let good = try accumulator.summary(now:30.1)
precondition(abs(good.rms + 40) < 0.001 && good.spread == 0)
let clipped = CommunityAccumulator()
for i in 0...300 { clipped.add(level: -40, peak: i == 10 ? 0 : -20, samples: 4800, rate: 48000, channels: 1, time: Double(i)/10) }
do { _ = try clipped.summary(now:30.1); fatalError("Clipping accepted") } catch {}
do { _ = try accumulator.summary(now:35); fatalError("Stale capture accepted") } catch {}
let gap = CommunityAccumulator()
gap.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:0)
gap.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:30)
do { _ = try gap.summary(now:30.1); fatalError("Interrupted capture accepted") } catch {}
let data = try CommunityPayload.data(id: UUID(), at: Date(timeIntervalSince1970:1792875780), lat:37.77012345,lon:-122.42012345,rms:good.rms,spread:good.spread,profile:"qc-community-v1:test-phone:48000:1")
let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
let c = body["contribution"] as! [String:Any]
precondition(c["lat"] as! Double == 37.770 && c["lon"] as! Double == -122.420)
precondition(Set(c.keys) == ["id","schema_version","area_id","area_name","lat","lon","time_bucket","duration_seconds","measurement","quality","source"])
precondition(body["share_consent"] as! Bool)
try data.write(to:URL(fileURLWithPath:"/tmp/qc-community-check/payload.json"))
print("PASS: energy average, clipping, gaps, stale capture, coarse coordinates and upload contract")
