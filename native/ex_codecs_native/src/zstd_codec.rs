use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

use crate::atoms;

fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut owned = OwnedBinary::new(data.len()).expect("allocation failed");
    owned.as_mut_slice().copy_from_slice(data);
    Binary::from_owned(owned, env).encode(env)
}

pub fn version() -> String {
    "1.5.x".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
    let level = level.clamp(1, 22);

    match zstd::bulk::compress(data.as_slice(), level) {
        Ok(compressed) => (atoms::ok(), encode_binary(env, &compressed)).encode(env),
        Err(_) => (atoms::error(), atoms::compression_failed()).encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match zstd::decode_all(data.as_slice()) {
        Ok(decompressed) => (atoms::ok(), encode_binary(env, &decompressed)).encode(env),
        Err(_) => (atoms::error(), atoms::decompression_failed()).encode(env),
    }
}