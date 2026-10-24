# Quiet Compass

**A shared sound layer for personal agents.**

Product brief · October 24, 2026  
Context: Personal Agents Hackathon, San Francisco  
Status: visual prototype with Oura integration code; sensing, shared observations, and a working MCP server remain to be built.

## The idea

Quiet Compass lets a personal agent help someone find a place that fits their acoustic needs, current task, and available time.

With permission, a phone measures short samples of its surroundings and keeps useful acoustic memories. Its agent can contribute a limited summary to a shared map. Other agents can query that map to help their own users. Personal preferences, private routes, conversations, and health information stay outside the shared layer.

The map is the visible surface of this system. The product is the service that agents use to make better decisions about physical places.

**One person's permitted observation can help another person's agent make a more informed recommendation.**

## The problem and first user

Finding a place on a map does not tell you whether its current sound environment will work for you. A park can host an amplified event. A café can be comfortable for conversation but distracting for focused work. A quiet area at an event can become crowded minutes later.

Our first user is an attendee in San Francisco who wants to keep participating in an event but needs a quieter place for a short break or task.

Potential users include people with sound sensitivities, some autistic people, some people with ADHD, and anyone looking for a suitable place to concentrate or talk. These are recruitment groups for user research, not predefined acoustic profiles. Preferences differ between people and situations.

The initial problem to validate is specific:

> “I need a place where I can finish something or take a break, nearby, and get back on time.”

We have not yet demonstrated demand, clinical benefit, or improved concentration.

## The pitch

Your personal agent knows what you need to do. Quiet Compass gives it a memory of how places sound.

With your permission, your phone processes short sound samples locally. Your agent remembers the places that worked for you and can share a small acoustic summary. Other agents contribute too, building a map that becomes more useful where people actually go.

When you need a quieter place, your agent considers recent observations, your preferences, and how much time you have. It proposes an option, explains the uncertainty, and checks conditions again when you arrive.

We are starting with events in San Francisco: helping people stay involved while finding environments that work for them.

## A concrete experience

The following is a proposed scenario; locations and observations are illustrative.

1. You arrive at an event near downtown San Francisco and enable a short measurement session.
2. Your phone samples an authorized area and records relative sound levels. You mark one space as comfortable.
3. Another participant opts to contribute a summary from a different area.
4. You tell your agent: “I need ten minutes to focus before the presentations.”
5. The agent queries nearby observations, checks their age, and considers your time limit and previously stated preferences.
6. It suggests a candidate with an explanation: “The courtyard had fewer abrupt changes in the latest observation. That was six minutes ago. We can check again when you arrive.”
7. At the destination, your phone takes another sample. The agent revises its recommendation if conditions have changed.
8. You can give brief feedback. That feedback updates your private preferences.

A return reminder would require a connected reminder or calendar service. A route or walking-time estimate would require an appropriate navigation source. Neither capability is currently implemented.

## How the agents work together

There are three separate kinds of information:

| Layer | Contents | Access |
| --- | --- | --- |
| Personal memory | Preferences, explicit feedback, permitted visit history, optional wearable context | The user and authorized personal agent |
| Shared observations | Coarse place or zone, time bucket, acoustic summary, measurement method, quality | The shared service, subject to its release policy |
| Public map | Released aggregates, observation age, coverage, uncertainty | Map viewers and querying agents |

The contribution exchange should be voluntary. People can use the service without turning on a microphone or contributing their location.

A shared map point should represent an observation or aggregate. It should never reveal a person's live position or imply that a visible pulse is a tracked individual.

### Proposed architecture

~~~mermaid
flowchart TD
    A["Phone collector"] --> B["Local acoustic summary"]
    B --> C["Private personal agent"]
    B -->|Opt-in contribution| D["Validation and aggregation"]
    D --> E["Shared sound layer"]
    E -->|MCP query| C
    E --> F["White and violet map"]
~~~

The phone collector must obtain operating-system permissions. MCP provides an interface for tools and context; it does not itself grant microphone access or keep a phone recording in the background. [1]

## The MCP interface

Start with three tools that match the existing visual contract:

| Proposed tool | Purpose | Essential response details |
| --- | --- | --- |
| query_sound_map | Retrieve released observations in an area | Source, measurement kind, age, coverage, quality |
| find_suitable_places | Find candidates for a goal and constraints | Candidate locations, supporting observations, uncertainty |
| submit_observation | Accept a consented acoustic summary | Validation result and whether it was accepted, withheld, or rejected |

These names are a proposed contract. There is no working MCP endpoint in the current prototype.

Keep personal ranking on the user's side where possible. The shared service can return candidates; the personal agent can apply preferences without uploading a diagnosis, calendar, health history, or detailed route.

A future agent skill should instruct the agent to:

- Check freshness and measurement compatibility before comparing places.
- Treat missing data as unknown.
- Separate measured observations from predictions and simulated data.
- Ask for sensor consent through the collector before any capture.
- Explain why a candidate may fit the user's current goal.
- Recheck at arrival when the user permits it.
- Avoid promising silence, access to a building, or medical benefit.

Example contribution shape, with invented demonstration values:

~~~json
{
  "schema_version": "0.1",
  "area_id": "sample-venue-courtyard",
  "time_bucket": "2026-10-24T17:00:00Z",
  "duration_seconds": 30,
  "measurement": {
    "kind": "relative_uncalibrated",
    "rms_dbfs": -31.4,
    "frame_level_spread_db": 8.2,
    "calibrated": false
  },
  "quality": {
    "capture_profile": "sample-profile-v1",
    "clipping_detected": false
  },
  "source": "simulated"
}
~~~

This is a schema proposal, not a real reading. The payload contains no raw recording, transcript, health data, or route. An actual implementation still needs validation, authentication, abuse controls, and a defined retention policy.

## How to measure sound

The first technical milestone is consistent comparison with the same phone and capture configuration.

Use short, user-initiated windows, initially around 30 seconds. Locally calculate signal energy, variation across frames, clipping, and abrupt changes. Record the capture configuration and quality indicators with the result.

Keep three questions separate:

| Question | Proposed method | Limitation |
| --- | --- | --- |
| How strong is the recorded signal? | RMS and frame-level statistics | Uncalibrated digital levels depend on the device and processing |
| How variable is it? | Distribution of frame levels and transient heuristics | Thresholds need validation |
| What might be producing it? | Optional local sound classifier | A class score does not measure loudness or personal comfort |

**Do not label uncalibrated dBFS values as dBA.** Cross-device absolute levels require a calibrated, validated measurement path. NIOSH's sound-level app is a useful example of measurement validation; its accuracy claims do not transfer to our implementation. [2]

Do not merge incompatible phone readings into a universal violet scale. Until cross-device validation exists, keep cohorts separate or present explicitly limited comparisons.

A single microphone sample does not tell us which nearby space is quieter. That recommendation needs observations at other locations. Spatial audio, camera tracking, and LiDAR can be later experiments; they are not dependencies for the first useful product.

## Dataset and model choices

| Resource | Useful role | Important boundary |
| --- | --- | --- |
| NoiseCapture | Existing crowdsourced acoustic mapping precedent and candidate observation source | Audit SF coverage, freshness, calibration metadata, and license before using it |
| SONYC-UST-V2 | Evaluate urban sound labels on real environmental recordings | Its recordings come from New York; they are not current SF observations |
| YAMNet | Candidate pretrained baseline for optional local event classification | Hardware performance and relevant labels still need testing |

NoiseCapture documents geographic exports and measurement metadata. We have not verified that its SF coverage is sufficient for this product. [3]

SONYC-UST-V2 supplies urban sound annotations with spatial and temporal evaluation structure. It is a useful research dataset for classification, rather than a substitute for local measurements. [4]

YAMNet predicts 521 audio-event classes and expects mono audio at 16 kHz. It is a candidate to evaluate, not a model already running in the prototype. [5]

For the hackathon, prioritize a working measurement-to-agent loop over training a custom model.

## Privacy and trust

Privacy is a design requirement that still needs implementation and testing.

Proposed defaults:

- Process audio locally and discard short-lived raw buffers after extracting the permitted features.
- Make capture sessions visible, time-limited, and easy to stop.
- Disable contribution until the user opts in.
- Keep routes, preferences, and wearable data in the private layer.
- Share coarse locations and bucketed times.
- Withhold sparse public aggregates rather than exposing individual visits.
- Rate-limit submissions and check duplicate, implausible, or incompatible measurements.
- Separate short-lived ingestion records from released aggregates.
- Provide deletion and retention controls.

As an initial design experiment, evaluate roughly 100-meter outdoor cells and five-minute time buckets. Indoor venues may use designated zones. These settings are proposals, not guarantees of anonymity.

Even coarse place-time data can reveal sensitive patterns. Persistent identifiers, infrastructure logs, and repeated queries need a threat model. Do not market the current prototype as anonymous, differentially private, or secured by cryptographic aggregation.

## Oura's role

Oura is optional personal context. It does not measure the surrounding noise or locate quieter spaces.

A user might explicitly choose a rule such as: “On days when I report feeling tired, prioritize shorter walks and familiar places.” Wearable summaries could supplement that preference with consent, without being treated as proof of sensory overload.

The current code contains an Oura OAuth flow and retrieval of sleep, readiness, and activity summaries. A successful end-to-end test with a real authorized account has not been verified. The prototype does not provide a live physiological overload detector.

Wearable data must remain outside the shared sound map.

## Visual design

The interface should make the map the main object:

- White background and restrained grayscale geography.
- Buildings and recognizable landmarks.
- Violet intensity for a clearly defined, comparable acoustic quantity.
- White or uncolored areas for unknown coverage.
- Small pulses for new released contributions.
- Selectable points revealing measurement type, age, and uncertainty.
- A compact MCP control and optional instructions.
- A visible simulated-data label whenever the data is synthetic.
- Reduced-motion support and accessible text alternatives.

Color must not simultaneously encode noise level, confidence, and personal suitability. Keep those meanings separate.

## Build the smallest convincing prototype

Start with one event and three authorized zones. Keep San Francisco as the map context.

The target scenario:

1. Take a real short sample in one zone.
2. Show the local summary and explicit sharing choice.
3. Submit the permitted summary.
4. Have a second agent query the shared service.
5. Let that agent explain a recommendation using the observation and its age.
6. Move to the candidate and compare a fresh reading.
7. Save optional comfort feedback privately.

If two devices cannot yet be compared reliably, demonstrate a sequential route measured with one device. Any replay or seeded data must be labeled.

Oura, citywide coverage, autonomous notifications, route optimization, and sound-source direction are later additions.

## What exists today

| Capability | Current status |
| --- | --- |
| Interactive SF map and landmark markers | Implemented visual prototype |
| White/grayscale map with violet intensity | Implemented with synthetic acoustic scores |
| Animated contribution pulses | Simulated |
| MCP button and tool contract | Implemented UI; server not connected |
| Oura OAuth and data-fetching code | Present; real-account integration not verified end to end |
| Phone audio collector and acoustic DSP | Not implemented |
| Shared observation database and ingestion | Not implemented |
| Public aggregate privacy controls | Proposed |
| Cross-device calibration | Not validated |
| Personal preference learning | Proposed |
| Automatic recommendations and follow-up actions | Proposed |

The downloadable source snapshot includes the map and Oura code. A push to the team's GitHub main branch has not been verified.

## What could make this fail

| Risk | What to test |
| --- | --- |
| Places change before people arrive | Check recommendations against fresh arrival measurements |
| Phone processing overwhelms real acoustic differences | Repeat controlled comparisons across orientations and devices |
| “Quieter” does not mean “better for me” | Collect task-specific, optional feedback |
| There are too few contributions | Begin in a bounded event with known measurement opportunities |
| The sharing flow feels intrusive | Test whether people understand and choose it voluntarily |
| Existing venue information already solves the task | Compare against a simple list of designated quiet spaces |
| The map looks impressive but changes no decision | Observe whether participants actually use and accept recommendations |

The strongest early result would be a participant finding a more suitable place through a recommendation grounded in recent observations. We do not yet have that result.

Measure time to find a suitable place, agreement with arrival conditions, usefulness reported by participants, battery impact, query latency, and sharing comprehension. Define success criteria before running the pilot.

## Keeping the service affordable

Run signal processing on the phone. Send compact summaries in batches. Cache map queries by area and time bucket. Use deterministic validation and aggregation; reserve LLM calls for user requests and explanation.

As an illustrative capacity scenario, 50 opted-in participants contributing once every two minutes for four hours would produce 6,000 submissions. That is a sizing assumption, not measured usage or a hosting quote. Actual cost also depends on reads, storage, map traffic, model calls, and provider terms.

A venue pilot is the first distribution hypothesis. Event organizers could invite participants and designate measurable zones. A commercial model remains unvalidated.

## The decision

Build the shared observation loop first: **measure locally → contribute with consent → query from another agent → recommend with evidence → recheck**.

That is the demonstration that makes Quiet Compass a personal-agent product. The city map shows where its shared knowledge exists; the personal agent turns that knowledge into help for one person.

## References

References were checked on October 24, 2026. They support technical background, not validation of Quiet Compass.

1. [Model Context Protocol — Architecture overview](https://modelcontextprotocol.io/docs/learn/architecture).
2. [CDC / NIOSH — Sound Level Meter App](https://www.cdc.gov/niosh/noise/about/app.html).
3. [Noise-Planet — Exploit NoiseCapture data](https://noise-planet.org/noisecapture_exploit_data.html).
4. [SONYC-UST-V2, version 2.3 — Dataset record](https://zenodo.org/records/3966543).
5. [TensorFlow — Sound classification with YAMNet](https://www.tensorflow.org/hub/tutorials/yamnet).

Project link: https://quiet-compass-oura-martin.martin-puli.chatgpt.site/  
Team repository: https://github.com/chiara-ciriani/hackathon-personal-agent

