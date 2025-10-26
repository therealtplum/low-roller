import React, { useState } from "react";
export default function Replay({events}:{events:any[]}) {
  const [i,setI]=useState(events.length-1);
  const e = events[i];
  return (
    <div className="replay">
      <div>Replay — {events.length} events</div>
      <div className="controls">
        <button onClick={()=>setI(0)} disabled={i<=0}>⏮</button>
        <button onClick={()=>setI(i-1)} disabled={i<=0}>◀</button>
        <span> {i+1}/{events.length} </span>
        <button onClick={()=>setI(i+1)} disabled={i>=events.length-1}>▶</button>
        <button onClick={()=>setI(events.length-1)} disabled={i>=events.length-1}>⏭</button>
      </div>
      <pre className="event">{JSON.stringify(e, null, 2)}</pre>
    </div>
  );
}
