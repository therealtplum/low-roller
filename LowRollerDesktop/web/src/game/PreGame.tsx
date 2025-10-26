// src/game/PreGame.tsx
import React, { useEffect, useMemo, useState } from "react";

export type BotLevel = "Amateur" | "Pro";

type SeatCfg = {
  isBot: boolean;
  botLevel: BotLevel;
  name: string;         // used if not a bot
  wagerCents: number;   // per-seat buy-in (humans & bots)
};

export type StartSeat = {
  display: string;
  is_bot: boolean;
  bot_level: BotLevel | null;
  wager_cents: number;
};

export type StartOpts = {
  youStart: boolean;
  seats: StartSeat[];   // Seat 1..N in order (Seat 1 is You)
};

const clamp = (v:number, lo:number, hi:number) => Math.max(lo, Math.min(hi, v));

export default function PreGame({
  name,
  onStart,
}: {
  name: string;
  onStart: (opts: StartOpts) => void;
}) {
  const [count, setCount] = useState<number>(() =>
    clamp(parseInt(localStorage.getItem("lowroller_seatcount") || "2", 10) || 2, 2, 8)
  );
  const [youStart, setYouStart] = useState<boolean>(
    (localStorage.getItem("lowroller_youstart") || "1") === "1"
  );

  // ✅ keep YOUR wager in React state
  const [yourWagerCents, setYourWagerCents] = useState<number>(() =>
    clamp(parseInt(localStorage.getItem("lowroller_wager") || "500", 10), 100, 10000)
  );
  useEffect(() => {
    localStorage.setItem("lowroller_wager", String(yourWagerCents));
  }, [yourWagerCents]);

  // heuristic defaults for bots
  const defaultBotWager = (level: BotLevel, humanWager = yourWagerCents) =>
    level === "Amateur"
      ? clamp(Math.round(Math.min(humanWager, 1500)), 100, 2500) // conservative
      : clamp(Math.round(humanWager * 1.2), 100, 10000);         // Pro: ~120%

  const [seats, setSeats] = useState<SeatCfg[]>(
    () => {
      const saved = localStorage.getItem("lowroller_seats_v2");
      if (saved) return JSON.parse(saved) as SeatCfg[];
      return Array.from({ length: 7 }, (_, i) => {
        const isBot = i === 0; // seat 2 bot by default
        const level: BotLevel = "Amateur";
        return {
          isBot,
          botLevel: level,
          name: `Player ${i + 2}`,
          wagerCents: isBot ? defaultBotWager(level) : yourWagerCents,
        };
      });
    }
  );

  // clamp seat wagers
  useEffect(() => {
    setSeats(prev => prev.map(s => ({ ...s, wagerCents: clamp(Math.round(s.wagerCents), 100, 10000) })));
  }, []);

  // when YOUR wager changes, only update bot defaults that still match the previous default
  // (avoid overwriting user-edited seat wagers)
  useEffect(() => {
    setSeats(prev => prev.map(s => {
      if (!s.isBot) return s;
      const newDefault = defaultBotWager(s.botLevel, yourWagerCents);
      // if seat equals *either* old Amateur/Pro default near old human wager, nudge it to new default
      // heuristic: if within $2 of an old default, treat as default
      const asDollars = (c:number) => Math.round(c/100);
      const dNow = asDollars(s.wagerCents);
      const dDef = asDollars(newDefault);
      if (Math.abs(dNow - dDef) <= 2) return { ...s, wagerCents: newDefault };
      return s;
    }));
  }, [yourWagerCents]); // eslint-disable-line react-hooks/exhaustive-deps

  // persist seat config
  useEffect(() => {
    localStorage.setItem("lowroller_seats_v2", JSON.stringify(seats));
  }, [seats]);

  useEffect(() => { setCount(c => clamp(c, 2, 8)); }, [count]);

  const potPreview = useMemo(() => {
    const others = seats.slice(0, count - 1).reduce((sum, s) => sum + clamp(s.wagerCents, 100, 10000), 0);
    return yourWagerCents + others;
  }, [seats, count, yourWagerCents]);

  function setSeat(i: number, fn: (s: SeatCfg) => SeatCfg) {
    setSeats(prev => {
      const cp = [...prev];
      cp[i] = fn(cp[i]);
      return cp;
    });
  }

  function start() {
    localStorage.setItem("lowroller_seatcount", String(count));
    localStorage.setItem("lowroller_youstart", youStart ? "1" : "0");

    const table: StartSeat[] = [
      { display: name || "You", is_bot: false, bot_level: null, wager_cents: yourWagerCents },
      ...seats.slice(0, count - 1).map((s) =>
        s.isBot
          ? {
              display: `${s.botLevel} 🤖`,
              is_bot: true,
              bot_level: s.botLevel,
              wager_cents: clamp(s.wagerCents, 100, 10000),
            }
          : {
              display: s.name || "Player",
              is_bot: false,
              bot_level: null,
              wager_cents: clamp(s.wagerCents, 100, 10000),
            }
      ),
    ];
    onStart({ youStart, seats: table });
  }

  return (
    <div className="pregame">
      <div className="card big">
        <div className="title">Start a New Game</div>

        <div className="row">
          <label>Player</label>
          <div className="value">{name}</div>
        </div>

        {/* Count stepper */}
        <div className="row">
          <label>Players</label>
          <div className="value" style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
            <button onClick={() => setCount(c => clamp(c - 1, 2, 8))} aria-label="decrease">–</button>
            <input
              type="number"
              min={2}
              max={8}
              value={count}
              onChange={(e) => setCount(clamp(parseInt(e.target.value || "2", 10), 2, 8))}
              style={{ width: 56, textAlign: "center" }}
            />
            <button onClick={() => setCount(c => clamp(c + 1, 2, 8))} aria-label="increase">+</button>
            <span style={{ opacity: 0.7 }}>(2–8)</span>
          </div>
        </div>

        {/* ✅ Your buy-in uses state now */}
        <div className="row">
          <label>Your buy-in</label>
          <div className="value">
            <div className="money-input">
              <span>$</span>
              <input
                type="number"
                min={1}
                max={100}
                step={1}
                value={Math.round(yourWagerCents / 100)}
                onChange={(e) =>
                  setYourWagerCents(clamp((parseInt(e.target.value || "1", 10)) * 100, 100, 10000))
                }
              />
            </div>
          </div>
        </div>

        {/* Seats grid */}
        <div className="row" style={{ alignItems: "flex-start" }}>
          <label>Seats 2–{count}</label>
          <div className="value">
            <div className="seats-grid">
              {seats.slice(0, count - 1).map((s, i) => (
                <div className="seat-card" key={i}>
                  <div className="seat-head">
                    <div className="seat-title">Seat {i + 2}</div>
                    <label className="chk">
                      <input
                        type="checkbox"
                        checked={s.isBot}
                        onChange={(e) => setSeat(i, (old) => {
                          const isBot = e.target.checked;
                          return {
                            ...old,
                            isBot,
                            // when toggling to bot, auto-set wager using heuristic; when to human, copy your current wager
                            wagerCents: isBot ? defaultBotWager(old.botLevel, yourWagerCents) : yourWagerCents,
                          };
                        })}
                      />
                      Bot
                    </label>
                  </div>

                  {!s.isBot ? (
                    <input
                      className="name-input"
                      placeholder={`Player ${i + 2}`}
                      value={s.name}
                      onChange={(e) => setSeat(i, (old) => ({ ...old, name: e.target.value }))}
                    />
                  ) : (
                    <div className="bot-row">
                      <span>Level</span>
                      <select
                        value={s.botLevel}
                        onChange={(e) => setSeat(i, (old) => {
                          const lvl = e.target.value as BotLevel;
                          const newDefault = defaultBotWager(lvl, yourWagerCents);
                          // if wager still equals old default, nudge to new default
                          const wasDefault = old.wagerCents === defaultBotWager(old.botLevel, yourWagerCents);
                          return {
                            ...old,
                            botLevel: lvl,
                            wagerCents: wasDefault ? newDefault : old.wagerCents,
                          };
                        })}
                      >
                        <option>Amateur</option>
                        <option>Pro</option>
                      </select>
                    </div>
                  )}

                  <div className="money-input">
                    <span>$</span>
                    <input
                      type="number"
                      min={1}
                      max={100}
                      step={1}
                      value={Math.round(s.wagerCents / 100)}
                      onChange={(e) =>
                        setSeat(i, (old) => ({
                          ...old,
                          wagerCents: clamp((parseInt(e.target.value || "1", 10)) * 100, 100, 10000),
                        }))
                      }
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="row">
          <label>Who starts?</label>
          <div className="value">
            <label className="chk">
              <input
                type="checkbox"
                checked={youStart}
                onChange={(e) => setYouStart(e.target.checked)}
              />
              You start (uncheck = random)
            </label>
          </div>
        </div>

        <div className="actions">
          <button onClick={start}>Start Game</button>
        </div>

        <div className="note">
          Pot preview: <strong>${(potPreview / 100).toFixed(2)}</strong>
        </div>
      </div>
    </div>
  );
}