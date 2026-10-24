export type PointFeature<P = Record<string, unknown>> = {
  type: 'Feature';
  geometry: {type: 'Point'; coordinates: number[]};
  properties: P;
};
export type PointCollection<P = Record<string, unknown>> = {
  type: 'FeatureCollection';
  features: PointFeature<P>[];
};
