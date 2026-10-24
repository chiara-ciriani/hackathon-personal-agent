import type { Metadata } from 'next';
import './globals.css';
export const metadata:Metadata={title:'Quiet Compass · Sound map',description:'The sound layer of San Francisco for personal agents.'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
