// Public visitor information checked on 2026-10-24. Coordinates identify the
// venue vicinity, not a verified entrance. Visitor facts never imply a sound level.
export type VenueSource={label:string;url:string};
export type VenueFact={summary:string;note:string;source:VenueSource};
export type VenuePlan={id:string;title:string;scope:string;image:string;imageAlt:string;url:string;source:VenueSource;edition:string};
export type VenueInfo={
 id:string;name:string;lng:number;lat:number;address:string;description:string;
 checkedOn:string;timeZone:'America/Los_Angeles';measurement:null;
 hours:VenueFact;access:VenueFact;facilities:VenueFact;plans:VenuePlan[];planNote:string;
};
const moscone={label:'Moscone visitor information',url:'https://moscone.com/directions-and-parking-moscone-center'};
const mosconePlans={label:'Moscone floor plans',url:'https://www.moscone.com/guidelines/floor-plans'};
const mason={label:'Fort Mason visitor information',url:'https://fortmason.org/visit/'};
const gallery={label:'Gallery 308 venue details',url:'https://fortmason.org/our-venues/gallery-308/'};
const ferry={label:'Ferry Building visitor information',url:'https://www.ferrybuildingmarketplace.com/visit/'};
const gardens={label:'Yerba Buena visitor information',url:'https://yerbabuenagardens.org/visit/general-information/'};
const chase={label:'Chase Center visitor guide',url:'https://www.chasecenter.com/plan-your-visit/a-to-z-guide/'};
const chaseAccess={label:'Chase Center accessible services',url:'https://www.chasecenter.com/plan-your-visit/accessible-services/'};
const checked={checkedOn:'2026-10-24',timeZone:'America/Los_Angeles' as const,measurement:null};
export const venues:VenueInfo[]=[
 {
  ...checked,id:'moscone',name:'Moscone Center',lng:-122.4010,lat:37.7842,
  address:'747 Howard Street, San Francisco · administrative office',
  description:'North, South and West are separate buildings. Choose the building and floor named on your event information.',
  hours:{summary:'Check your event schedule',note:'Visitor opening times have not been verified. Confirm with your event organizer.',source:moscone},
  access:{summary:'Confirm your building and entrance',note:'Moscone West is at 800 Howard Street. The pin is not a verified entrance; confirm admission with your organizer.',source:moscone},
  facilities:{summary:'Official plans by building and floor',note:'The North/South lobby plan identifies rooms and circulation areas. Event layouts and accessible routes need confirmation on site.',source:mosconePlans},
  plans:[{id:'north-south-lobby',title:'North & South · lobby level',scope:'Lobby floor only. Does not include Moscone West.',image:'/plans/moscone-lobby.png',imageAlt:'Official Moscone North and South lobby floor plan with Howard Street and numbered meeting rooms.',url:'https://www.moscone.com/sites/default/files/floor_plans/pdf/MCNS-Lobby%20Level_20240430%20full%20set.pdf',source:{label:'Moscone lobby plan and full PDF',url:'https://www.moscone.com/floorplans/moscone-north-south-lobby-level-floor-plan'},edition:'Operator PDF dated April 30, 2024 · page 1'}],
  planNote:'Published floor plan. Room access and event arrangements may change.',
 },
 {
  ...checked,id:'chase',name:'Chase Center',lng:-122.3877,lat:37.7680,
  address:'Mission Bay, San Francisco · venue vicinity',
  description:'Check the current event guide for entry and support services before choosing a place to take a break.',
  hours:{summary:'Event hours need confirmation',note:'Current door times could not be verified from the visitor guide.',source:chase},
  access:{summary:'Check admission and re-entry',note:'Confirm the rules for your event before planning a break outside the arena.',source:chase},
  facilities:{summary:'Sensory support documented; confirm current access',note:'The Warriors’ 2022–23 report describes a sensory room. Its current location and availability have not been verified.',source:{label:'Warriors community report, 2022–23',url:'https://cdn.warriors.com/impact-report/CR%20Impact%20Report%2022-23.pdf'}},
  plans:[],planNote:'No current official floor plan has been verified for this guide. Check the venue’s accessible services for help finding a suitable space.',
 },
 {
  ...checked,id:'fortmason',name:'Fort Mason Center',lng:-122.4320,lat:37.8067,
  address:'2 Marina Boulevard, San Francisco',
  description:'A campus with separate galleries, theaters and event spaces. A plan for one room does not describe the whole campus.',
  hours:{summary:'Hours vary by organization and event',note:'The main office is open Monday–Friday, 9am–5pm, except listed holidays. These are office hours, not campus opening hours.',source:mason},
  access:{summary:'Confirm the specific building',note:'Check your organization or event for visitor access. Gallery 308 is an event rental space.',source:gallery},
  facilities:{summary:'Gallery 308 has an outdoor patio',note:'The operator also publishes a floor plan and 3D tour. Patio availability depends on the event.',source:gallery},
  plans:[{id:'gallery-308',title:'Gallery 308',scope:'Gallery 308 only. Other Fort Mason buildings are not shown.',image:'/plans/gallery-308.png',imageAlt:'Official Gallery 308 floor plan with gallery, foyer, A.V. and storage marked no client access.',url:'https://fortmason.org/wp-content/uploads/2025/12/Floorplan.pdf',source:gallery,edition:'Operator download checked October 24, 2026 · page 1; drawing date not confirmed'}],
  planNote:'Published event-space plan. Storage marked “No client access” is not a visitor destination.',
 },
 {
  ...checked,id:'ferry',name:'Ferry Building',lng:-122.3935,lat:37.7955,
  address:'One Ferry Building, San Francisco',
  description:'The marketplace, outdoor plazas and individual shops have different visiting conditions.',
  hours:{summary:'Daily, 6am–10pm',note:'Building hours; individual shops vary. Closed Thanksgiving Day and Christmas Day.',source:ferry},
  access:{summary:'Marketplace and outdoor promenade',note:'Farmers market: Tuesday and Thursday, 10am–2pm; Saturday, 8am–2pm. A market schedule does not establish a sound level.',source:{label:'Official farmers market schedule',url:'https://www.ferrybuildingmarketplace.com/farmers-market/'}},
  facilities:{summary:'Public seating, accessible restrooms and WiFi',note:'Benches are on the promenade. Public restrooms are in the north and south terminal passages.',source:ferry},
  plans:[],planNote:'No floor plan has been verified for this guide. The visitor page provides building and access information.',
 },
 {
  ...checked,id:'yerba-buena-gardens',name:'Yerba Buena Gardens',lng:-122.4023,lat:37.7854,
  address:'750 Howard Street, San Francisco',
  description:'Public gardens with a published accessibility map. This listing is for the gardens, not Yerba Buena Center for the Arts.',
  hours:{summary:'Daily, 6am–10pm',note:'Public restrooms: daily, 9am–5pm. Individual facilities may have different hours.',source:gardens},
  access:{summary:'Free admission to the gardens',note:'Individual facilities and amenities may charge a fee. Consult the accessibility map for points of access.',source:gardens},
  facilities:{summary:'Accessible routes, public restrooms and WiFi',note:'The operator publishes an ADA map. Check the event calendar before visiting; performances can change the experience.',source:gardens},
  plans:[{id:'gardens-accessibility',title:'Gardens · accessibility map',scope:'Outdoor campus and access points. Not an indoor floor plan.',image:'/plans/yerba-buena.png',imageAlt:'Official Yerba Buena Gardens accessibility map with campus facilities and accessible points of access.',url:'https://yerbabuenagardens.org/wp-content/uploads/2025/10/ADA-Map-Oct-2025.pdf',source:gardens,edition:'Operator map dated October 2025 · page 1'}],
  planNote:'Published accessibility map. Conditions along a route still need checking when you arrive.',
 },
];
export const DEFAULT_VENUE_ID='moscone';
// Preserve old links without confusing the gardens with the arts center.
export function venueById(id:string|null|undefined):VenueInfo|undefined{
 const resolved=id==='ybca'?'yerba-buena-gardens':id??DEFAULT_VENUE_ID;
 return venues.find(v=>v.id===resolved);
}
export const venueVisitorSource=(venue:VenueInfo):VenueSource=>venue.id==='chase'?chaseAccess:venue.hours.source;
export const venueMapProperties=(venue:VenueInfo)=>({
 id:venue.id,label:venue.name,name:venue.name,kind:'Venue',evidence:'unmeasured_candidate',
 detail:venue.hours.summary,
 caveat:'No sound measurement is linked to this venue. The pin shows its vicinity, not a verified entrance.',
});
