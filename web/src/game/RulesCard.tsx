import React, { useState } from "react";
export default function RulesCard(){
  const [open, setOpen] = useState(true);
  return (
    <div className={`rules ${open?"open":"closed"}`}>
      <div className="rules-header" onClick={()=>setOpen(!open)}>
        <strong>Rules</strong>
        <span className="spacer" />
        <button className="small">{open?"Hide":"Show"}</button>
      </div>
      {open && (
        <ul>
          <li>Goal: <b>lowest total</b> wins. <b>3 counts as 0</b>.</li>
          <li>Each turn: roll remaining dice, then set aside <b>at least one</b>. Repeat until all 7 are set aside.</li>
          <li>See others' live rolls & totals to strategize.</li>
          <li>5:00 timer; on expiry, a fallback move is auto-picked.</li>
          <li>Tie: sudden death — each rolls 1 die; lowest wins (3→0).</li>
        </ul>
      )}
    </div>
  );
}
