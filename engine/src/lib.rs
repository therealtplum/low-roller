pub mod model;
pub mod rng;
pub mod rules;
pub mod bot;

use model::*;
use rand::{SeedableRng, rngs::StdRng, Rng};
use rules::{face_score, sum_score};
use serde_json::json;

fn hash_state_stub(s: &State) -> String {
    format!("h:{}:{}:{}", s.turn_idx, s.remaining_dice, s.players[s.turn_idx].picks.len())
}

pub fn init_game(seed: u64, mut players: Vec<Player>) -> State {
    let pot_cents = players.iter().map(|p| p.wager_cents).sum();
    let mut rng = StdRng::seed_from_u64(seed ^ 0x5EED);
    players.shuffle(&mut rng);
    State {
        seed, players, turn_idx: 0, remaining_dice: 7, last_faces: vec![],
        must_pick_at_least_one: true, pot_cents, phase: Phase::Normal,
        events_seq: 0, per_turn_deadline_ms: None, leader_to_beat: None,
    }
}

pub fn roll(state: &mut State) -> Event {
    assert!(matches!(state.phase, Phase::Normal));
    assert!(state.remaining_dice > 0);
    let mut rng = StdRng::seed_from_u64(state.seed ^ (state.events_seq as u64).wrapping_mul(7919));
    let mut faces = Vec::with_capacity(state.remaining_dice);
    for _ in 0..state.remaining_dice { faces.push(((rng.gen::<u8>() % 6) + 1) as u8); }
    state.last_faces = faces;
    state.must_pick_at_least_one = true;
    state.events_seq += 1;
    Event { seq: state.events_seq, ty: EventType::Roll, payload: json!({ "faces": state.last_faces }), state_hash: hash_state_stub(state) }
}

pub fn pick(state: &mut State, indices: &[usize]) -> Event {
    assert!(!state.last_faces.is_empty());
    assert!(!indices.is_empty());
    let mut idxs = indices.to_vec();
    idxs.sort_unstable(); idxs.dedup();
    let mut picked_vals: Vec<u8> = Vec::with_capacity(idxs.len());
    for (k, &i) in idxs.iter().enumerate() {
        assert!(i < state.last_faces.len(), "index OOB at {}", k);
        picked_vals.push(face_score(state.last_faces[i]));
    }
    let p = &mut state.players[state.turn_idx];
    p.picks.extend(picked_vals.iter().copied());
    p.total_score = sum_score(&p.picks) as u32;
    let mut remaining: Vec<u8> = Vec::with_capacity(state.last_faces.len() - idxs.len());
    for (i, &f) in state.last_faces.iter().enumerate() {
        if !idxs.contains(&i) { remaining.push(f); }
    }
    state.remaining_dice = remaining.len();
    state.last_faces.clear();
    state.must_pick_at_least_one = false;
    state.events_seq += 1;
    Event { seq: state.events_seq, ty: EventType::Pick, payload: json!({ "picked": idxs, "values": picked_vals }), state_hash: hash_state_stub(state) }
}

pub fn end_turn_if_done(state: &mut State) -> Option<Event> {
    if state.remaining_dice == 0 {
        state.events_seq += 1;
        let total = state.players[state.turn_idx].total_score;
        let ev = Event { seq: state.events_seq, ty: EventType::EndTurn, payload: json!({ "playerIdx": state.turn_idx, "total": total }), state_hash: hash_state_stub(state) };
        let next_idx = (state.turn_idx + 1) % state.players.len();
        let last_player = state.turn_idx == state.players.len() - 1;
        state.turn_idx = next_idx; state.remaining_dice = 7;
        state.last_faces.clear(); state.must_pick_at_least_one = true;
        if last_player {
            // compute winner(s)
            let mut lows: Vec<usize> = vec![]; let mut low = u32::MAX;
            for (i, pl) in state.players.iter().enumerate() {
                if pl.total_score < low { low = pl.total_score; lows.clear(); lows.push(i); }
                else if pl.total_score == low { lows.push(i); }
            }
            if lows.len() > 1 { state.phase = Phase::SuddenDeath(lows.iter().map(|&i| state.players[i].id.clone()).collect()); }
            else { state.phase = Phase::Finished; }
        }
        Some(ev)
    } else { None }
}

pub fn timeout_autoplay(state: &mut State) -> Event {
    let mut rng = StdRng::seed_from_u64(state.seed ^ (state.events_seq as u64).wrapping_mul(104729));
    state.leader_to_beat = compute_leader_to_beat(state);
    let decision = crate::bot::amateur_policy_public(state, &mut rng);
    let ev = pick(state, &decision);
    Event { seq: ev.seq, ty: EventType::TimeoutAutoplay, payload: serde_json::json!({ "chosen": ev.payload, "policy": "amateur_v1" }), state_hash: ev.state_hash.clone() }
}

fn compute_leader_to_beat(state: &State) -> Option<u32> {
    let cur_id = state.players[state.turn_idx].id.clone();
    let mut best = u32::MAX; let mut found = false;
    for p in &state.players {
        if p.id != cur_id && !p.picks.is_empty() {
            found = true; if p.total_score < best { best = p.total_score; }
        }
    }
    if found { Some(best) } else { None }
}
