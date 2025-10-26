import React from "react";
export default function Confirm({open, title, body, onConfirm, onCancel}:{open:boolean; title:string; body:string; onConfirm:()=>void; onCancel:()=>void}){
  if (!open) return null;
  return (
    <div className="modal-backdrop">
      <div className="modal">
        <div className="modal-title">{title}</div>
        <div className="modal-body">{body}</div>
        <div className="modal-actions">
          <button className="danger" onClick={onConfirm}>Yes</button>
          <button onClick={onCancel}>Cancel</button>
        </div>
      </div>
    </div>
  );
}
