use rustler::{Binary, Env, Term};

use crate::atoms;
use crate::util::{err, ok_binary, output_within_limit};

pub fn version() -> String {
    "lz4_flex-0.11".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let compressed = lz4_flex::compress_prepend_size(data.as_slice());
    ok_binary(env, &compressed)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_decompress<'a>(env: Env<'a>, data: Binary, max_output_size: u64) -> Term<'a> {
    let slice = data.as_slice();
    if slice.len() < 4 {
        return err(env, atoms::decompression_failed());
    }
    let claimed = u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]) as usize;
    if !output_within_limit(claimed, max_output_size) {
        return err(env, atoms::output_limit_exceeded());
    }

    match lz4_flex::decompress_size_prepended(slice) {
        Ok(decompressed) => {
            if !output_within_limit(decompressed.len(), max_output_size) {
                return err(env, atoms::output_limit_exceeded());
            }
            ok_binary(env, &decompressed)
        }
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
