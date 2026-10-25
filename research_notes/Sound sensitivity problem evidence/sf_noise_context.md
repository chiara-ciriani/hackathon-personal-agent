# San Francisco noise and sensory-access context (for the Quiet Compass pitch)

Researched 2026-10-24. The DataSF numbers are live SoQL queries run that day (both datasets were last updated 2026-10-23 23:59). "YTD" means 2026-01-01 to 2026-10-23. Dataset plumbing is in `reports/Más datos sonoros de SF.md` and isn't repeated here.

**Top 8 slide-ready facts**
1. San Franciscans have filed 17,542 noise complaints with 311 so far in 2026, up 90% from 9,211 at the same point in 2025. [DataSF 311 vw6y-z8j6](https://data.sf.gov/resource/vw6y-z8j6.json)
2. Adding police "NOISE NUISANCE" calls (14,230 YTD) brings the total to about 31,800 noise reports in 2026, roughly 107 a day. [DataSF CAD 2zdj-bwza](https://data.sf.gov/resource/2zdj-bwza.json) + [311](https://data.sf.gov/resource/vw6y-z8j6.json)
3. The 311 noise volume has grown every year since 2021: 7,324 (2021), 8,259 (2023), 9,864 (2024), 11,893 (2025), and 17,542 by October 2026. [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
4. The Tenderloin, the Mission and SoMa account for 37% of 2026 noise complaints (3,194, 2,231 and 1,122). [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
5. 311 has a dedicated "major event venue" noise category. It logged 831 complaints in 2026 YTD, already more than all of 2025 (661). Mission Bay, home of Chase Center, is one of the top areas. [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
6. BART trains have been measured at 95 dB in the Transbay Tube and 86-88 dB underground, above OSHA's 85 dB 8-hour workplace limit. These readings are from 2003 and 2019. [Bay Crossings](https://www.baycrossings.com/bart-quietly-makes-repairs/); [KALW 2019](https://www.kalw.org/show/crosscurrents/2019-03-26/will-bart-damage-my-hearing)
7. Sensory support exists only in a few fixed rooms (Chase Center, Oracle Park, SFO Terminal 1), and these spaces only help people who are already inside those venues. [CBS SF](https://www.cbsnews.com/sanfrancisco/news/exclusive-chase-center-is-first-sensory-inclusive-venue-in-bay-area); [SF Autism Society](https://sfautismsociety.org/sfo-opens-first-sensory-room/)
8. Crowds are big. Outside Lands expected about 75,000 people a day in Golden Gate Park in August 2026, and Dreamforce 2025 drew over 40,000 in person to Moscone. [GrowSF](https://growsf.org/news/2026-08-06-outside-lands-expands-muni-and-bay-wheels-service/); [SalesforceBen](https://www.salesforceben.com/dreamforce/)

Caveat for facts 1 and 3: 311 renamed its category from "Noise Report" to "Noise" in 2024, and in 2026, 68% of reports came from the mobile app. Part of the 2026 jump may come from easier reporting and not only from more noise. Present it as "reported noise complaints," not "noise levels."

## 1. How much does SF complain about noise? (311 + police CAD)

### Takeaway
Reported noise is at a record high in 2026. 311 complaints are up 90% from the same point last year, and combined 311 and police noise reports average about 107 a day. The reports cluster in the Tenderloin, the Mission and SoMa.

### Cited Findings
- 311 noise cases by year (service_name "Noise Report" or "Noise"): 2016: 3,798 · 2017: 5,388 · 2018: 6,630 · 2019: 7,520 · 2020: 11,238 · 2021: 7,324 · 2022: 7,340 · 2023: 8,259 · 2024: 9,864 · 2025: 11,893 · 2026 YTD: 17,542 — [DataSF 311 vw6y-z8j6](https://data.sf.gov/resource/vw6y-z8j6.json)
- 2025 through Oct 24: 9,211 vs 2026 through Oct 23: 17,542 (+90%) — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- The category was "Noise Report" through 2024 and "Noise" from 2024 on (2024 split: 3,624 / 6,240). In 2026, 11,870 of 17,542 came via the mobile app, 4,168 via web and 1,356 by phone — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- 2026 monthly volume peaked in spring: 2,142 (Mar), 2,122 (Apr), 2,315 (May) — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- Top 2026 subtypes: other excessive noise 10,452; amplified sound/electronics 1,585; entertainment 1,343; major event venue 831; private construction 830; public construction 664; mechanical equipment 385; garbage collection 350; traffic 216; sirens 169 — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- 2025 subtypes for comparison: other excessive 5,461; amplified sound 1,322; entertainment 1,131; private construction 734; major event venue 661 — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- Top neighborhoods in 2026 YTD: Tenderloin 3,194; Mission 2,231; Western Addition 1,218; SoMa 1,122; Mission Bay 696; Hayes Valley 688; Bayview Hunters Point 662; Nob Hill 609; Marina 542 — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- Top neighborhoods in 2025: Mission 1,698; Tenderloin 1,203; SoMa 816; Oceanview/Merced/Ingleside 645; Nob Hill 601 — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- "Major event venue" complaints, 2025 through 2026 YTD, by neighborhood: Mission 376; Mission Bay 236; Bayview Hunters Point 98; Tenderloin 89; Golden Gate Park 83 — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)
- SFPD "NOISE NUISANCE" dispatch calls by year: 2015: 23,501 · 2019: 20,987 · 2020: 25,405 (peak) · 2021: 23,147 · 2022: 18,985 · 2023: 16,869 · 2024: 16,795 · 2025: 16,612 · 2026 YTD: 14,230. The same period in 2025 had 13,648, so 2026 is running 4% higher — [DataSF CAD 2zdj-bwza](https://data.sf.gov/resource/2zdj-bwza.json)
- Combined 311 and CAD noise reports: 2025 about 28,505 (about 78/day); 2026 YTD about 31,772 (about 107/day), 39% above the same period in 2025 — computed from the two datasets above

### Inferences
- 2026 already has more combined noise reports than all of 2025 had, more than two months before year-end.
- Police noise calls have dropped since 2020 while 311 complaints have climbed. Some complaints may be moving from police to 311 and its app. That's an inference; neither dataset shows it directly.
- The neighborhoods with the most complaints are also where SF's convention and event venues are: Moscone in SoMa, Chase Center in Mission Bay, and nightlife in the Mission and Tenderloin.

### Gaps
- Complaints measure annoyance and willingness to report, not decibels.
- I don't know why "other_excessive_noise" doubled in 2026. It could be an app or category change, and I didn't check that.
- The 2026 figures are year-to-date through Oct 23. They are not annualized.

## 2. Measured and modeled noise levels in SF

### Takeaway
The BART decibel readings are real, but most are old (2003-2019). I found no recent BART-published measurement. SFDPH has a street-level traffic noise model that flags areas above 60 Ldn, but I couldn't confirm a "percent of residents above 60 dB" figure. Don't use one on the slide.

### Cited Findings
- 2003: a Bay Crossings decibel meter measured about 70 dB on straight BART track, about 80 dB on curves, and 95 dB at three Transbay Tube spots, one lasting nearly three minutes. After rail grinding in 2004, those spots dropped to 79-81 dB with brief 86 dB peaks — [Bay Crossings](https://www.baycrossings.com/bart-quietly-makes-repairs/)
- 2019: a KALW test measured about 86-88 dB on average in underground BART segments — [KALW](https://www.kalw.org/show/crosscurrents/2019-03-26/will-bart-damage-my-hearing)
- 2016: wheel and rail noise, including the screech on curves, can reach about 90 dB. Engineers said the Transbay Tube walls amplify it. BART planned tapered wheel profiles for a possible 50% noise cut — [NBC Bay Area](https://www.nbcbayarea.com/news/local/bart-seeks-to-quiet-its-loud-trains/1966800)
- 2019: a Mercury News reader measured 84.3 dB on a new car and 84.7 dB on an old car. BART said noise complaints fell 73% after wheel reprofiling began — [Mercury News via PressReader](https://www.pressreader.com/usa/the-mercury-news-weekend/20190802/281578062277650)
- 2010: BART says it runs two rail grinders and three wheel lathes, measures noise routinely, and that operators sometimes wear earplugs — [BART.gov](https://www.bart.gov/node/13138)
- A Chronicle-based report cites 100 dB in the Transbay Tube. I didn't see the original, so that figure is unverified — [search snippet via ABC7 archive](https://abc7news.com/archive/7654122)
- SFDPH's 2007 transportation noise model estimates traffic noise for every street in SF and flags areas above 60 Ldn. Building inspectors use it to decide which projects need acoustic review — [SFDPH noise](https://sfdph.org/dph/EH/Noise/noiseresponse.asp)
- A peer-reviewed SF study (Seto et al., 2007) estimated that about 17% of San Franciscans were at risk of high annoyance from traffic noise — [Int J Health Geographics](https://ij-healthgeographics.biomedcentral.com/track/pdf/10.1186/1476-072X-6-24); [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC1914342)

### Inferences
- "BART can exceed 85 dB, the OSHA 8-hour limit" is supportable, but cite the year. The Transbay Tube is the loudest stretch.

### Gaps
- No 2024-2026 BART measurement or report.
- No verified "% of SF population above 60 dB Ldn" figure. The 17% figure is about annoyance, and it dates from 2007.
- I didn't research Muni noise figures. For SFO aircraft data, see the existing report.

## 3. Big events and crowds

### Takeaway
SF regularly packs tens of thousands of people into single venues and festivals, and these settings are where sensory overload happens.

### Cited Findings
- Dreamforce 2025 (Oct 14-16, Moscone Center) had over 40,000 in-person attendees and over 200,000 online registrants. Another guide claimed 150,000+ in person; that figure is unreliable and conflicts with SalesforceBen — [SalesforceBen](https://www.salesforceben.com/dreamforce/); [Outdoo](https://www.outdoo.ai/blog/dreamforce-2025-your-ultimate-guide)
- Outside Lands organizers expected about 75,000 people a day for Aug 7-9, 2026, in Golden Gate Park — [GrowSF](https://growsf.org/news/2026-08-06-outside-lands-expands-muni-and-bay-wheels-service/)
- Outside Lands has drawn over 200,000 people per festival in most years since 2008 — [Ingleside Light](https://www.inglesidelight.com/outside-lands-2025-a-weekend-full-of-standout-artists-and-food/)
- Event-venue noise shows up in the city's own data, with 831 "major event venue" 311 complaints in 2026 YTD (see section 1) — [DataSF 311](https://data.sf.gov/resource/vw6y-z8j6.json)

### Gaps
- I found no official total for Moscone's annual attendance.
- Not verified: Bay to Breakers 2025/2026 participant counts, and Chase Center (about 18,000) and Oracle Park (about 41,000) capacities. These are commonly cited, but I didn't fetch a source, so check them before using.

## 4. Sensory access in SF

### Takeaway
A few large venues have sensory rooms or kits: Chase Center, Oracle Park and SFO. Each one only helps inside its own building. None tells anyone where a quiet spot is nearby right now, and that's the gap Quiet Compass fills.

### Cited Findings
- Chase Center has been KultureCity Certified Sensory Inclusive since 2019. It was the first such venue in the Bay Area and has a Wellness and Sensory Room open for all Warriors games, concerts and events. The room was later renovated and dedicated to Simu Liu. Sensory bags with noise-canceling headphones, fidget tools and weighted lap pads are available at Portals 13 and 52 — [CBS SF](https://www.cbsnews.com/sanfrancisco/news/exclusive-chase-center-is-first-sensory-inclusive-venue-in-bay-area); [Arena Digest](https://arenadigest.com/2019/12/26/chase-center-wellness-and-sensory-room-unveiled/); [KultureCity news](https://www.kulturecity.org/category/latest-news/page/16/)
- KultureCity certification requires at least 50% of staff to be trained. A sensory room is optional — [Arena Digest](https://arenadigest.com/2019/09/10/chase-center-certified-as-sensory-inclusive-venue/)
- Oracle Park is KultureCity certified and lends free sensory bags at the Promenade Guest Services desk with an ID deposit. A "Sensory Pod" quiet space was added in Lower Center Field in 2026. This comes from the search summary of the Giants' page; a direct fetch failed with HTTP 406 — [Giants accessible services](https://www.mlb.com/giants/ballpark/accessible-services)
- SFO opened its first sensory room in December 2024, post-security in Harvey Milk Terminal 1, open 5am-11pm. It has activity and calming areas and a mock aircraft cabin, and it is unstaffed. It was built with UCSF Children's Hospital and The Arc SF — [SF Autism Society](https://sfautismsociety.org/sfo-opens-first-sensory-room/); [Stuck at the Airport](https://stuckattheairport.com/2024/12/16/sfo-airport-adds-a-sensory-room/)

### Gaps
- Not verified: sensory-friendly hours at the Exploratorium or Cal Academy, SF Public Library quiet rooms, Moscone sensory or quiet rooms, Mayor's Office on Disability resources, and the KultureCity directory list for SF. My searches returned nothing SF-specific.

## 5. How many autistic people live in SF?

### Takeaway
No direct count exists. The proxies are regional-center caseloads (GGRC serves SF, Marin and San Mateo) and school special-ed counts. The 3,524 figure from the brief could not be verified.

### Cited Findings
- Golden Gate Regional Center serves people with developmental disabilities in Marin, San Francisco and San Mateo. It served about 8,700 people in 2016-17, with autism at about 22% of consumers. The chart text was garbled, so treat 22% as approximate — [DDS GGRC performance report 2016](https://www.dds.ca.gov/wp-content/uploads/2019/03/Transparency_GGPCYR2016_20190228.pdf)
- About 6,483 SFUSD students received special education in 2023 (13.3% of enrollment). This is a secondary citation of a district presentation — [Google Doc export](https://docs.google.com/document/d/11zAD8eTbtfE3o3H2Nn0-R9J6Oe5IMex2dhUeXROIE8o/export?format=pdf)
- Autism diagnoses among SF students rose 51% from FY2016-17 to FY2019-20, per a Board of Supervisors Budget and Legislative Analyst report. Search snippet only; the PDF didn't parse — [SF BLA report, Mar 2022](https://sfbos.archive.sf.gov/sites/default/files/BLA.Special%20Ed.%20Finance.031622.a.pdf)
- SF added 685 students with disabilities in 2024-25 (+9.2%, vs a 3.4% state average). This is a Substack analysis of CDE data, a secondary source — [SF Education Substack](https://sfeducation.substack.com/p/the-impending-crisis-in-special-education)
- SFUSD runs autism-focused special day classes from Pre-K to age 22 and says it is expanding supports for a "growing population of autistic students" — [SFUSD](https://www.sfusd.edu/es/node/20240)

### Inferences
- An estimate method, for pitch use only and clearly labeled as an estimate: apply the CDC's prevalence estimate (about 1 in 36 children, 2023 ADDM) or an adult estimate (about 2.2%) to SF's population. I didn't fetch the CDC source this session, so verify before using.

### Gaps
- GGRC "3,524 autistic clients FY2024-25" is unverified. The DDS autism-by-regional-center PDF (https://www.dds.ca.gov/wp-content/uploads/2021/04/AutismGrowthRCCaseloadGrowth.pdf) didn't parse in this environment. Check the DDS "Facts and Stats" page or ggrc.org.
- No exact SFUSD autism enrollment found. Use CDE DataQuest special-ed by disability for SFUSD 2024-25.
