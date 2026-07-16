use rustler::{Binary, Env, Term};

use crate::atoms;
use crate::util::{err, ok_binary};

pub fn version() -> String {
    "lz4_flex-0.11".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let compressed = lz4_flex::compress_prepend_size(data.as_slice());
    ok_binary(env, &compressed)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match lz4_flex::decompress_size_prepended(data.as_slice()) {
        Ok(decompressed) => ok_binary(env, &decompressed),
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
