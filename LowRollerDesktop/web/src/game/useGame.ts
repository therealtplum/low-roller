// src/game/useGame.ts
import { useState, useRef, useEffect } from "react";
import { Engine } from "./engine";
import type { StartSeat } from "./PreGame";

// ---------------- Types ----------------
type BotLevel = "Amateur" | "Pro";

// Old (2-player) options you may still pass from older PreGame
type StartOptsV1 = {
  wagerCents: number;
  botLevel: BotLevel;
  botWagerCents: number;
  youStart: boolean;
};

// New (multi-seat) options from the new PreGame
type StartOptsV2 = {
  youStart: boolean;
  seats: StartSeat[];
};

type StartArg = number | StartOptsV1 | StartOptsV2;

// --------------- Hook ------------------
export function useGame() {
  const [state, setState] = useState<any | null>(null);
  const [events, setEvents] = useState<any[]>([]);
  const [picked, setPicked] = useState<number[]>([]);
  const [rolling, setRolling] = useState(false);
  const [preGame, setPreGame] = useState(true);

  const engRef = useRef<Engine | null>(null);
  const nameRef = useRef<string>(localStorage.getItem("lowroller_name") || "You");
  const wagerRef = useRef<number>(
    parseInt(localStorage.getItem("lowroller_wager") || "500", 10)
  );

  // ---------- helpers ----------
  function pushEvent(ev: any) {
    setEvents((prev) => [...prev, ev]);
  }
  function isYourTurnNow() {
    return !!state && !state.players[state.turn_idx].is_bot;
  }

  // ---------- name & init ----------
  function setPlayerName(n: string) {
    nameRef.current = n || "You";
    localStorage.setItem("lowroller_name", nameRef.current);
    if (state) {
      const ns = { ...state };
      ns.players = [...ns.players];
      ns.players[0] = { ...ns.players[0], display: nameRef.current };
      setState(ns);
    }
  }
  function initLocal() {
    /* lobby flow */
  }

  // ---------- start game (supports v1, v2, number) ----------
  function startNewGame(arg?: StartArg) {
    let youStart = true;

    // Engine player list we’ll pass in
    let players: Array<{
      id: string;
      display: string;
      is_bot: boolean;
      bot_level: BotLevel | null;
      wager_cents: number;
    }> = [];

    if (typeof arg === "object" && arg !== null && "seats" in arg) {
      // ✅ New lobby format (multi-seat)
      const seats = arg.seats;
      youStart = arg.youStart ?? true;

      players = seats.map((s, idx) => ({
        id: idx === 0 ? "you" : `p${idx + 1}`,
        display: s.display,
        is_bot: s.is_bot,
        bot_level: (s.bot_level ?? null) as BotLevel | null,
        wager_cents: s.wager_cents,
      }));

      // keep "your" wager around for defaults elsewhere
      if (seats[0]?.wager_cents != null) {
        wagerRef.current = seats[0].wager_cents;
        localStorage.setItem("lowroller_wager", String(wagerRef.current));
      }
    } else if (typeof arg === "object" && arg !== null) {
      // ✅ Old 2-player format
      const w = arg.wagerCents;
      const botW = arg.botWagerCents;
      youStart = arg.youStart ?? true;

      players = [
        { id: "you", display: nameRef.current, is_bot: false, bot_level: null, wager_cents: w },
        { id: "bot1", display: `${arg.botLevel} 🤖`, is_bot: true, bot_level: arg.botLevel, wager_cents: botW },
      ];
      wagerRef.current = w;
      localStorage.setItem("lowroller_wager", String(w));
    } else {
      // ✅ Number or nothing: fallback to 1 human + 1 Amateur bot
      const w = typeof arg === "number" ? arg : wagerRef.current;
      players = [
        { id: "you", display: nameRef.current, is_bot: false, bot_level: null, wager_cents: w },
        { id: "bot1", display: "Amateur 🤖", is_bot: true, bot_level: "Amateur", wager_cents: w },
      ];
      youStart = true;
      wagerRef.current = w;
      localStorage.setItem("lowroller_wager", String(w));
    }

    // init engine
    engRef.current = new Engine(Date.now() >>> 0, players);

    const s = engRef.current.getState();
    s.turn_idx = youStart ? 0 : Math.floor(Math.random() * players.length);

    setEvents([]);
    setPicked([]);
    setState({ ...s });
    setPreGame(false);
  }

  // -------- Human actions (guarded by turn) --------
  function roll() {
    if (!engRef.current || !isYourTurnNow()) return;
    try {
      setRolling(true);
      const ev = engRef.current.roll();
      pushEvent(ev);
      setState({ ...engRef.current.getState() });
      setPicked([]);
    } finally {
      setTimeout(() => setRolling(false), 400);
    }
  }

  function togglePick(i: number) {
    if (!isYourTurnNow()) return;
    setPicked((p) => (p.includes(i) ? p.filter((x) => x !== i) : [...p, i]));
  }

  function confirmPick() {
    if (!engRef.current || !isYourTurnNow() || picked.length === 0) return;
    const ev = engRef.current.pick(picked);
    pushEvent(ev);
    setState({ ...engRef.current.getState() });
    setPicked([]);
    const end = engRef.current.endTurnIfDone();
    if (end) {
      pushEvent(end);
      setState({ ...engRef.current.getState() });
    }
  }

  function timeoutAutoplay() {
    if (!engRef.current) return;
    const s0 = engRef.current.getState();
    if ((s0.last_faces?.length || 0) === 0 && s0.remaining_dice > 0) {
      const r = engRef.current.roll();
      pushEvent(r);
      setState({ ...engRef.current.getState() });
    }
    const ev = engRef.current.timeoutAutoplay();
    pushEvent(ev);
    setState({ ...engRef.current.getState() });
    const end = engRef.current.endTurnIfDone();
    if (end) {
      pushEvent(end);
      setState({ ...engRef.current.getState() });
    }
  }

  function inProgress(): boolean {
    if (!state) return false;
    if (state.phase === "Finished") return false;
    if (state.last_faces?.length > 0) return true;
    if (state.players?.some((p: any) => (p.picks?.length || 0) > 0)) return true;
    return events.length > 0;
  }

  function backToPreGame() {
    setPreGame(true);
    setState(null);
    setEvents([]);
    setPicked([]);
  }

  // -------- Bot loop (works for any number of bots) --------
  function botStep() {
    if (!engRef.current || !state) return;
    const cur = state.players[state.turn_idx];
    if (!cur.is_bot || state.phase === "Finished") return;

    if ((state.last_faces?.length || 0) === 0 && state.remaining_dice > 0) {
      const r = engRef.current.roll();
      pushEvent(r);
      setState({ ...engRef.current.getState() });
      return;
    }
    const ev = engRef.current.timeoutAutoplay();
    pushEvent(ev);
    setState({ ...engRef.current.getState() });
    const end = engRef.current.endTurnIfDone();
    if (end) {
      pushEvent(end);
      setState({ ...engRef.current.getState() });
    }
  }

  useEffect(() => {
    if (!state) return;
    if (state.players[state.turn_idx]?.is_bot) {
      const id = setTimeout(botStep, 350);
      return () => clearTimeout(id);
    }
  }, [state?.turn_idx, state?.last_faces, state?.remaining_dice, state?.phase]);

  return {
    state,
    events,
    picked,
    togglePick,
    confirmPick,
    roll,
    rolling,
    timeoutAutoplay,
    initLocal,
    setPlayerName,
    preGame,
    startNewGame,
    inProgress,
    backToPreGame,
  };
}