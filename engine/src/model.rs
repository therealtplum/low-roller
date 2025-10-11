use serde::{Deserialize, Serialize};

pub type PlayerId = String;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum BotLevel { Amateur, Pro }

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum EventType {
    Roll,
    Pick,
    EndTurn,
    TimeoutAutoplay,
    SuddenDeathRoll,
    GameEnd,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Event {
    pub seq: u64,
    pub ty: EventType,
    pub payload: serde_json::Value,
    pub state_hash: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Player {
    pub id: PlayerId,
    pub display: String,
    pub is_bot: bool,
    pub bot_level: Option<BotLevel>,
    pub wager_cents: u32,
    pub total_score: u32,
    pub picks: Vec<u8>, // 3s stored as 0
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum Phase {
    Normal,
    SuddenDeath(Vec<PlayerId>),
    Finished,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct State {
    pub seed: u64,
    pub players: Vec<Player>,
    pub turn_idx: usize,
    pub remaining_dice: usize,
    pub last_faces: Vec<u8>,
    pub must_pick_at_least_one: bool,
    pub pot_cents: u32,
    pub phase: Phase,
    pub events_seq: u64,
    pub per_turn_deadline_ms: Option<u128>,
    pub leader_to_beat: Option<u32>,
}
