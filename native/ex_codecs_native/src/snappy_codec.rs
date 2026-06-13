use rustler::{Binary, Encoder, Env, Term};

use crate::atoms;
use crate::util::encode_binary;

pub fn version() -> String {
    "1.1.x".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn snappy_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let mut encoder = snap::raw::Encoder::new();
    match encoder.compress_vec(data.as_slice()) {
        Ok(compressed) => (atoms::ok(), encode_binary(env, &compressed)).encode(env),
        Err(_) => (atoms::error(), atoms::compression_failed()).encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn snappy_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let mut decoder = snap::raw::Decoder::new();
    match decoder.decompress_vec(data.as_slice()) {
        Ok(decompressed) => (atoms::ok(), encode_binary(env, &decompressed)).encode(env),
        Err(_) => (atoms::error(), atoms::decompression_failed()).encode(env),
    }
}