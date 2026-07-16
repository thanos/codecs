use rustler::{Binary, Env, Term};

use crate::atoms;
use crate::util::{err, ok_binary};

pub fn version() -> String {
    "snap-1.1".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn snappy_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let mut encoder = snap::raw::Encoder::new();
    match encoder.compress_vec(data.as_slice()) {
        Ok(compressed) => ok_binary(env, &compressed),
        Err(_) => err(env, atoms::compression_failed()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn snappy_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let mut decoder = snap::raw::Decoder::new();
    match decoder.decompress_vec(data.as_slice()) {
        Ok(decompressed) => ok_binary(env, &decompressed),
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
