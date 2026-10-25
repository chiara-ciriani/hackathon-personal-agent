import type {Metadata} from 'next';
import PhoneMeasurement from './phone-measurement';
import './measure.css';

export const metadata: Metadata = {
  title: 'Connect your phone · Quiet Compass',
  description: 'Connect your phone so your agent can measure nearby sound and recommend where to go. No audio uploaded.',
};
export default function MeasurePage() { return <PhoneMeasurement/>; }
