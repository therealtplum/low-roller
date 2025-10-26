use crate::{model::{State, BotLevel}, rules::{face_score, REROLL_EV}};
use rand::{Rng, rngs::StdRng};

pub struct BotDecision { pub pick_indices: Vec<usize> }

pub fn bot_pick(state: &State, level: BotLevel, rng: &mut StdRng) -> BotDecision {
    match level { BotLevel::Amateur => amateur_policy(state, rng), BotLevel::Pro => pro_policy(state, rng) }
}

pub(crate) fn amateur_policy(state: &State, rng: &mut StdRng) -> BotDecision {
    let faces = &state.last_faces;
    let mut threes: Vec<usize> = faces.iter().enumerate().filter(|(_, &f)| f == 3).map(|(i,_)| i).collect();
    if !threes.is_empty() { return BotDecision { pick_indices: threes }; }
    let mut lowest = 0usize;
    for i in 1..faces.len() {
        let a = face_score(faces[lowest]); let b = face_score(faces[i]);
        if b < a { lowest = i; }
    }
    let mut picks = vec![lowest];
    if let Some(leader) = state.leader_to_beat {
        let current_total = state.players[state.turn_idx].picks.iter().map(|&v| v as u32).sum::<u32>();
        let remaining_after = state.remaining_dice - picks.len();
        let mut extra_ones: Vec<usize> = faces.iter().enumerate().filter(|(i,&f)| *i != lowest && f == 1).map(|(i,_)| i).collect();
        let added = (1u32 * extra_ones.len() as u32) + face_score(faces[lowest]) as u32;
        let ev_line = current_total + added + (REROLL_EV * remaining_after as f32).round() as u32;
        if ev_line <= leader { picks.extend(extra_ones.drain(..)); }
    }
    if faces.len() > 1 && rng.gen::<u8>() % 5 == 0 { picks.reverse(); }
    BotDecision { pick_indices: picks }
}

fn pro_policy(state: &State, _rng: &mut StdRng) -> BotDecision {
    let faces = &state.last_faces;
    let mut picks: Vec<usize> = faces.iter().enumerate().filter(|(_, &f)| f == 3).map(|(i,_)| i).collect();
    if !picks.is_empty() { return BotDecision { pick_indices: picks }; }
    let leader = state.leader_to_beat.unwrap_or(u32::MAX);
    let current_total: u32 = state.players[state.turn_idx].picks.iter().map(|&v| v as u32).sum();
    let mut ones: Vec<usize> = faces.iter().enumerate().filter(|(_, &f)| f == 1).map(|(i,_)| i).collect();
    let remaining_if_bank_ones = state.remaining_dice - ones.len();
    let ev_line_all_ones = current_total + (1 * ones.len() as u32)
        + (crate::rules::REROLL_EV * remaining_if_bank_ones as f32).round() as u32;
    if ev_line_all_ones <= leader && !ones.is_empty() {
        picks.append(&mut ones);
        return BotDecision { pick_indices: picks };
    }
    let mut lowest = 0usize;
    for i in 1..faces.len() {
        let a = face_score(faces[lowest]); let b = face_score(faces[i]);
        if b < a { lowest = i; }
    }
    BotDecision { pick_indices: vec![lowest] }
}

// public re-export for timeout fallback to call without exposing internals
pub fn amateur_policy_public(state: &State, rng: &mut StdRng) -> Vec<usize> {
    amateur_policy(state, rng).pick_indices
}
