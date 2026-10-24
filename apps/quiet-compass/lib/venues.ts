// Event venues shown as points on the city map. Levels are simulated (0 quiet .. 1 loud); `bias` shifts every zone inside the venue model.
export type VenueInfo={id:string;name:string;lng:number;lat:number;score:number;bias:number};
export const venues:VenueInfo[]=[
 {id:'moscone',name:'Moscone Center',lng:-122.4010,lat:37.7842,score:.78,bias:.1},
 {id:'chase',name:'Chase Center',lng:-122.3877,lat:37.7680,score:.88,bias:.16},
 {id:'fortmason',name:'Fort Mason Center',lng:-122.4320,lat:37.8067,score:.42,bias:-.14},
 {id:'ferry',name:'Ferry Building',lng:-122.3935,lat:37.7955,score:.64,bias:.02},
 {id:'ybca',name:'Yerba Buena Gardens',lng:-122.4023,lat:37.7854,score:.52,bias:-.04},
];
export const venueById=(id:string|null|undefined)=>venues.find(v=>v.id===id)??venues[0];
