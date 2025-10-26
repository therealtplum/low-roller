import React from "react";

type Row = { name: string; games: number; dollarsWon: number; streak: number };

function readBoard(): Row[] {
  try {
    return JSON.parse(localStorage.getItem("lowroller_board") || "[]");
  } catch {
    return [];
  }
}

export function writeResult({ winner, potCents }: { winner: string; potCents: number }) {
  const rows = readBoard();
  const byName = new Map(rows.map((r) => [r.name, r]));
  const w = byName.get(winner) || { name: winner, games: 0, dollarsWon: 0, streak: 0 };
  w.games += 1;
  w.dollarsWon += Math.round(potCents / 100);
  w.streak += 1;
  byName.set(winner, w);
  rows.forEach((r) => {
    if (r.name !== winner) r.streak = 0;
  });
  localStorage.setItem("lowroller_board", JSON.stringify(Array.from(byName.values())));
}

export default function Leaderboard() {
  const rows = readBoard().sort((a, b) => b.dollarsWon - a.dollarsWon || b.games - a.games);
  return (
    <div className="rules" style={{ marginTop: 16 }}>
      <div className="rules-header">
        <strong>Leaderboard (local)</strong>
      </div>
      {rows.length === 0 ? (
        <div className="note">Play a few games to populate the board.</div>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th align="left">Player</th>
              <th align="right">Games Won</th>
              <th align="right">$ Won</th>
              <th align="right">Streak</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                <td>{r.name}</td>
                <td align="right">{r.games}</td>
                <td align="right">${r.dollarsWon}</td>
                <td align="right">{r.streak}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}