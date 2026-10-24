import {Compass,MapPin,Route,Calendar,MessageCircle} from 'lucide-react';
import '../map.css';

export default function Event(){
 return <main className="quiet-unavailable-page">
  <a className="quiet-back" href="/"><Compass size={22}/>Volver al mapa</a>
  <section className="quiet-unavailable-panel"><MessageCircle size={44} strokeWidth={1}/><h1>Tu memoria del entorno</h1><p>Los datos aparecerán cuando conectes tu agente y compartas mediciones reales desde el teléfono.</p>
   <div className="quiet-empty-grid"><article><MapPin size={20}/><strong>Lugares medidos</strong><b>—</b><span>Sin datos personales conectados</span></article><article><Route size={20}/><strong>Recorrido</strong><b>—</b><span>Sin recorrido conectado</span></article><article><Calendar size={20}/><strong>Próxima actividad</strong><b>—</b><span>Sin calendario conectado</span></article></div>
   <p>No hay una conversación con un agente conectada a esta vista.</p><a className="quiet-source-link" href="/">Ver fuentes reales en el mapa</a><a className="quiet-source-link" href="/connections">Conectar Oura</a>
  </section>
 </main>;
}
