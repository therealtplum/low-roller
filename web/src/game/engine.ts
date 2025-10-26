// src/game/engine.ts

export type EventType =
  | "Roll"
  | "Pick"
  | "EndTurn"
  | "TimeoutAutoplay"
  | "TimeoutAutoplayNoop";

export type Event = {
  seq: number;
  ty: EventType;
  payload: any;
  state_hash: string; // placeholder for determinism / replay integrity
};

type Player = {
  id: string;
  display: string;
  is_bot: boolean;
  bot_level: "Amateur" | "Pro" | null;
  wager_cents: number;
  // runtime
  picks: number[];
  total_score: number;
};

type Phase = "Normal" | "Finished";

type State = {
  seed: number;
  players: Player[];
  turn_idx: number;
  remaining_dice: number;
  last_faces: number[]; // faces from the most recent roll; must pick from these before rolling again
  pot_cents: number;
  phase: Phase;

  // bookkeeping
  events_seq: number;
  per_turn_deadline_ms: number | null;
  leader_to_beat: number | null;

  // one round = every player takes exactly one full turn
  turns_taken: number;
};

const scoreFace = (f: number) => (f === 3 ? 0 : f);

export class Engine {
  private state: State;

  constructor(seed: number, playersIn: any[]) {
    const players: Player[] = playersIn.map((p: any) => ({
      id: p.id,
      display: p.display,
      is_bot: !!p.is_bot,
      bot_level: (p.bot_level ?? null) as Player["bot_level"],
      wager_cents: Number(p.wager_cents) | 0,
      picks: [],
      total_score: 0,
    }));

    const pot = players.reduce((s, p) => s + (p.wager_cents || 0), 0);

    this.state = {
      seed,
      players,
      // do NOT shuffle; seat 0 is the human by UI contract
      turn_idx: 0,
      remaining_dice: 7,
      last_faces: [],
      pot_cents: pot,
      phase: "Normal",
      events_seq: 0,
      per_turn_deadline_ms: null,
      leader_to_beat: null,
      turns_taken: 0, // completed turns in this round
    };
  }

  getState(): State {
    return this.state;
  }

  // ---------------- Core actions ----------------

  roll(): Event {
    // must pick from the previous roll before rolling again
    if (this.state.last_faces.length > 0) {
      throw new Error("Must set aside at least one die before rolling again");
    }
    if (this.state.remaining_dice <= 0) {
      throw new Error("No dice left to roll");
    }
    if (this.state.phase === "Finished") {
      throw new Error("Game already finished");
    }

    const faces = Array.from(
      { length: this.state.remaining_dice },
      () => 1 + Math.floor(Math.random() * 6)
    );
    this.state.last_faces = faces;

    return this.evt("Roll", { faces });
  }

  pick(indices: number[]): Event {
    if (this.state.phase === "Finished") {
      throw new Error("Game already finished");
    }
    if (!this.state.last_faces.length) {
      throw new Error("No roll to pick from");
    }

    // normalize / validate indices
    const uniq = Array.from(new Set(indices)).sort((a, b) => a - b);
    if (uniq.length === 0) {
      throw new Error("Must pick at least one die");
    }
    for (const i of uniq) {
      if (i < 0 || i >= this.state.last_faces.length) {
        throw new Error("Pick index out of range");
      }
    }

    // apply scoring rule (3 → 0)
    const scored = uniq.map((i) => scoreFace(this.state.last_faces[i]));

    const p = this.state.players[this.state.turn_idx];
    p.picks.push(...scored);
    p.total_score = p.picks.reduce((s, v) => s + v, 0);

    this.state.remaining_dice -= uniq.length;
    // clear faces so the next action must be a roll (unless turn ends)
    this.state.last_faces = [];

    return this.evt("Pick", {
      playerIdx: this.state.turn_idx,
      picked_indices: uniq,
      scored_values: scored,
      remaining_dice: this.state.remaining_dice,
      player_total: p.total_score,
    });
  }

  endTurnIfDone(): Event | null {
    if (this.state.remaining_dice > 0) return null;

    const endedIdx = this.state.turn_idx;
    const endedTotal = this.state.players[endedIdx].total_score;

    // mark one full turn as completed
    this.state.turns_taken += 1;

    // everyone gets exactly one turn in the round
    if (this.state.turns_taken >= this.state.players.length) {
      this.state.phase = "Finished";
    } else {
      // advance to next player; reset dice for new turn
      this.state.turn_idx = (this.state.turn_idx + 1) % this.state.players.length;
      this.state.remaining_dice = 7;
      this.state.last_faces = [];
    }

    return this.evt("EndTurn", {
      playerIdx: endedIdx,
      total: endedTotal,
      phase: this.state.phase,
      turns_taken: this.state.turns_taken,
    });
  }

  /**
   * Timeout fallback:
   * - If faces exist: auto-pick (prefer all 3s -> 0; else pick the single lowest-scoring face).
   * - If no faces exist: no-op (UI can roll() first, then call this again).
   */
  timeoutAutoplay(): Event {
    const faces = this.state.last_faces;
    if (!faces.length) {
      return this.evt("TimeoutAutoplayNoop", {});
    }

    // choose indices: all 3s or the single lowest (by scoreFace)
    const tripleIdx: number[] = [];
    for (let i = 0; i < faces.length; i++) if (faces[i] === 3) tripleIdx.push(i);

    const indicesToPick =
      tripleIdx.length > 0
        ? tripleIdx
        : [
            faces.reduce((bestI, f, i) => {
              const cur = scoreFace(f);
              const best = scoreFace(faces[bestI]);
              return cur < best ? i : bestI;
            }, 0),
          ];

    // Reuse normal pick flow so totals update consistently
    const evPick = this.pick(indicesToPick);
    // Mirror as "TimeoutAutoplay" in the stream for clarity
    return this.evt("TimeoutAutoplay", evPick.payload);
  }

  // ---------------- Helpers ----------------

  private evt(ty: EventType, payload: any): Event {
    this.state.events_seq += 1;
    return { seq: this.state.events_seq, ty, payload, state_hash: "h" };
    // NOTE: state_hash can be replaced with a real hash for deterministic replays
  }
}