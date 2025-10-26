#[inline] pub fn face_score(face: u8) -> u8 { if face == 3 { 0 } else { face } }
pub const REROLL_EV: f32 = 3.0;
pub fn sum_score(faces: &[u8]) -> u32 {
    faces.iter().map(|&f| face_score(f) as u32).sum()
}
