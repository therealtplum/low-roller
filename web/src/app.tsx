import React, { useEffect, useState } from "react";
import { useGame } from "./game/useGame";
import Dice from "./game/Dice";
import HUD from "./game/HUD";
import Replay from "./game/Replay";
import RulesCard from "./game/RulesCard";
import NameBox from "./game/NameBox";
import PreGame from "./game/PreGame";
import Confirm from "./game/Confirm";
import Leaderboard, { writeResult } from "./game/Leaderboard";

export default function App() {
  const g = useGame();
  const [mode, setMode] = useState<"play" | "replay">("play");
  const [confirmOpen, setConfirmOpen] = useState(false);

  // Save winner to leaderboard when a game finishes
  useEffect(() => {
    if (g.state?.phase === "Finished") {
      const players = g.state.players;
      const winner = players.reduce(
        (a: any, b: any) => (a.total_score <= b.total_score ? a : b)
      ).display;
      writeResult({ winner, potCents: g.state.pot_cents });
    }
  }, [g.state?.phase]);

  useEffect(() => {
    g.initLocal();
  }, []);

  const newGameClick = () => {
    if (g.inProgress()) setConfirmOpen(true);
    else g.backToPreGame(); // go to lobby; start from there
  };

  // PreGame screen (name + settings + leaderboard)
  if (g.preGame) {
    return (
      <div className="screen">
        <header className="topbar">
          <div className="brand">LOW ROLLER</div>
          <div className="spacer" />
          <NameBox onChange={(n) => g.setPlayerName(n)} />
        </header>

        <PreGame
          name={localStorage.getItem("lowroller_name") || "You"}
          onStart={(opts) => g.startNewGame(opts)}
        />

        <Leaderboard />
      </div>
    );
  }

  if (!g.state) return <div className="screen">Loading…</div>;

  const isFinished = g.state.phase === "Finished";
  const cur = g.state.players[g.state.turn_idx];
  const isYourTurn = !cur.is_bot;

  const players = g.state.players;
  const winner =
    isFinished
      ? players.reduce((a: any, b: any) =>
          a.total_score <= b.total_score ? a : b
        )
      : null;

  return (
    <div className="screen">
      <header className="topbar">
        <div className="brand">LOW ROLLER</div>
        <div className="spacer" />
        <NameBox onChange={(n) => g.setPlayerName(n)} />
        <button onClick={newGameClick}>New Game</button>
        <button onClick={() => setMode((m) => (m === "play" ? "replay" : "play"))}>
          {mode === "play" ? "Replay" : "Back to Table"}
        </button>
      </header>

      {mode === "play" ? (
        <div className="table">
          <div className="table-grid">
            <div className="lhs"><RulesCard /></div>
            <div className="rhs">
              <HUD g={g} />

              {!isFinished && !isYourTurn && (
                <div style={{ textAlign: "center", opacity: 0.85, marginBottom: 6 }}>
                  🤖 Bot is taking its turn…
                </div>
              )}

              {isFinished && (
                <div
                  style={{
                    margin: "8px 0 0",
                    textAlign: "center",
                    padding: "10px 12px",
                    borderRadius: 10,
                    background: "rgba(255,255,255,0.05)",
                    border: "1px solid rgba(255,255,255,0.15)",
                  }}
                >
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Game Over</div>
                  <div style={{ marginBottom: 6 }}>
                    Winner: <strong>{winner.display}</strong> — Total:{" "}
                    <strong>{winner.total_score}</strong> — Pot:{" "}
                    <strong>${(g.state.pot_cents / 100).toFixed(2)}</strong>
                  </div>
                  <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
                    <button onClick={newGameClick}>New Game</button>
                    <button onClick={() => setMode("replay")}>Replay</button>
                  </div>
                </div>
              )}

              <div className="tray">
                <Dice
                  faces={g.state.last_faces}
                  picked={g.picked}
                  onPickToggle={(i) => {
                    if (!isFinished && isYourTurn) g.togglePick(i);
                  }}
                />
              </div>

              <div className="controls">
                <button
                  disabled={
                    isFinished ||
                    !isYourTurn ||
                    g.rolling ||
                    g.state.remaining_dice === 0 ||
                    g.state.last_faces.length > 0
                  }
                  onClick={g.roll}
                >
                  Roll
                </button>
                <button
                  disabled={isFinished || !isYourTurn || g.picked.length === 0}
                  onClick={g.confirmPick}
                >
                  Set Aside
                </button>
                <button disabled={isFinished} onClick={g.timeoutAutoplay}>
                  Timeout Fallback
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <Replay events={g.events} />
      )}

      <Confirm
        open={confirmOpen}
        title="Forfeit current game?"
        body="Starting a new game now will forfeit the current one."
        onConfirm={() => {
          setConfirmOpen(false);
          g.backToPreGame();
        }}
        onCancel={() => setConfirmOpen(false)}
      />
    </div>
  );
}