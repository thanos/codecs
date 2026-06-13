use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

use crate::atoms;

fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut owned = OwnedBinary::new(data.len()).expect("allocation failed");
    owned.as_mut_slice().copy_from_slice(data);
    Binary::from_owned(owned, env).encode(env)
}

pub fn version() -> String {
    "1.10.x".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_compress<'a>(env: Env<'a>, data: Binary, _level: u32) -> Term<'a> {
    let compressed = lz4_flex::compress(data.as_slice());

    (atoms::ok(), encode_binary(env, &compressed)).encode(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let estimated_size = data.len() * 8;

    match lz4_flex::decompress(data.as_slice(), estimated_size) {
        Ok(decompressed) => (atoms::ok(), encode_binary(env, &decompressed)).encode(env),
        Err(_) => (atoms::error(), atoms::decompression_failed()).encode(env),
    }
}