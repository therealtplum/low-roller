import React, { useEffect, useState } from "react";
export default function HUD({g}:{g:any}) {
  const s = g.state!;
  const pot = (s.pot_cents/100).toFixed(2);
  const [msLeft, setMsLeft] = useState(5*60*1000);
  useEffect(()=>{
    const start = Date.now();
    const id = setInterval(()=> setMsLeft(5*60*1000 - (Date.now()-start)), 200);
    return ()=>clearInterval(id);
  }, [s.events_seq]);
  const mm = Math.max(0, Math.floor(msLeft/60000));
  const ss = Math.max(0, Math.floor((msLeft%60000)/1000)).toString().padStart(2,"0");
  return (
    <div className="hud">
      <div className="pot">💰 Pot: ${pot}</div>
      <div className="timer">⏱️ {mm}:{ss}</div>
      <div className="board">
        {s.players.map((p:any, idx:number)=>(
          <div key={p.id} className={`card ${idx===s.turn_idx?"active":""}`}>
            <div className="name">{p.display}{p.is_bot? " 🤖": ""}</div>
            <div className="score">Total: {p.total_score}</div>
            <div className="chips">Picked: {p.picks?.join(", ")||"—"}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
