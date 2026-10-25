import Foundation
struct AgentConnectionError: LocalizedError {
 let errorDescription: String?
 init(_ message:String){errorDescription=message}
}
let accumulator = CommunityAccumulator()
for i in 0...100 { accumulator.add(level: -40, peak: -20, samples: 4800, rate: 48000, channels: 1, time: Double(i)/10) }
let good = try accumulator.summary(now:10.1)
precondition(abs(good.rms + 40) < 0.001 && good.spread == 0)
let clipped = CommunityAccumulator()
for i in 0...100 { clipped.add(level: -40, peak: i == 10 ? 0 : -20, samples: 4800, rate: 48000, channels: 1, time: Double(i)/10) }
do { _ = try clipped.summary(now:10.1); fatalError("Clipping accepted") } catch {}
do { _ = try accumulator.summary(now:15); fatalError("Stale capture accepted") } catch {}
let gap = CommunityAccumulator()
gap.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:0)
gap.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:10)
do { _ = try gap.summary(now:10.1); fatalError("Interrupted capture accepted") } catch {}
let data = try CommunityPayload.data(id: UUID(), at: Date(timeIntervalSince1970:1792875780), lat:37.77012345,lon:-122.42012345,rms:good.rms,spread:good.spread,profile:"qc-community-v1:test-phone:48000:1")
let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
let c = body["contribution"] as! [String:Any]
precondition(c["lat"] as! Double == 37.770 && c["lon"] as! Double == -122.420)
precondition(Set(c.keys) == ["id","schema_version","area_id","area_name","lat","lon","time_bucket","duration_seconds","measurement","quality","source"])
precondition(body["share_consent"] as! Bool)
precondition(c["duration_seconds"] as! Int == 10)
let short = CommunityAccumulator()
short.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:0)
short.add(level:-40,peak:-20,samples:4800,rate:48000,channels:1,time:1)
do { _ = try short.summary(now:1.1); fatalError("Short capture accepted") } catch {}
try data.write(to:URL(fileURLWithPath:"/tmp/qc-community-check/payload.json"))
print("PASS: energy average, clipping, gaps, stale capture, coarse coordinates and upload contract")
