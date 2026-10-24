// Location directory only. No verified indoor plans or acoustic readings are available for these venues.
export type VenueInfo={id:string;name:string;lng:number;lat:number};
export const venues:VenueInfo[]=[
 {id:'moscone',name:'Moscone Center',lng:-122.4010,lat:37.7842},
 {id:'chase',name:'Chase Center',lng:-122.3877,lat:37.7680},
 {id:'fortmason',name:'Fort Mason Center',lng:-122.4320,lat:37.8067},
 {id:'ferry',name:'Ferry Building',lng:-122.3935,lat:37.7955},
 {id:'ybca',name:'Yerba Buena Gardens',lng:-122.4023,lat:37.7854},
];
export const venueById=(id:string|null|undefined)=>venues.find(v=>v.id===id)??venues[0];
