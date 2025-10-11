import React, { useEffect, useState } from "react";
export default function NameBox({onChange}:{onChange:(name:string)=>void}){
  const [name, setName] = useState<string>(()=> localStorage.getItem("lowroller_name") || "You");
  useEffect(()=>{ localStorage.setItem("lowroller_name", name); onChange(name); }, [name]);
  return (
    <div className="namebox">
      <label>Your name</label>
      <input value={name} onChange={e=>setName(e.target.value)} maxLength={24} />
    </div>
  );
}
