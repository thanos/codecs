use rustler::{Binary, Env, Term};

use crate::atoms;
use crate::util::{err, ok_binary, output_within_limit};

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
pub fn snappy_decompress<'a>(env: Env<'a>, data: Binary, max_output_size: u64) -> Term<'a> {
    match snap::raw::decompress_len(data.as_slice()) {
        Ok(claimed) if !output_within_limit(claimed, max_output_size) => {
            return err(env, atoms::output_limit_exceeded());
        }
        Ok(_) => {}
        Err(_) => return err(env, atoms::decompression_failed()),
    }

    let mut decoder = snap::raw::Decoder::new();
    match decoder.decompress_vec(data.as_slice()) {
        Ok(decompressed) => {
            if !output_within_limit(decompressed.len(), max_output_size) {
                return err(env, atoms::output_limit_exceeded());
            }
            ok_binary(env, &decompressed)
        }
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
