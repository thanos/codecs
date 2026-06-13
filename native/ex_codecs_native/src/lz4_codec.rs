use rustler::{Binary, Encoder, Env, Term};

use crate::atoms;
use crate::util::encode_binary;

pub fn version() -> String {
    "1.10.x".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let compressed = lz4_flex::compress_prepend_size(data.as_slice());

    (atoms::ok(), encode_binary(env, &compressed)).encode(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match lz4_flex::decompress_size_prepended(data.as_slice()) {
        Ok(decompressed) => (atoms::ok(), encode_binary(env, &decompressed)).encode(env),
        Err(_) => (atoms::error(), atoms::decompression_failed()).encode(env),
    }
}