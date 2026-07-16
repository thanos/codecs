use rustler::{Binary, Env, Term};
use std::io::Read;

use crate::atoms;
use crate::util::{err, ok_binary};

pub fn version() -> String {
    "ruzstd-0.8".to_string()
}

fn compression_level(level: i32) -> ruzstd::encoding::CompressionLevel {
    // ruzstd only fully implements Fastest today; map all positive levels there
    // and keep Uncompressed for level 0 edge cases (Elixir validates 1..=22).
    match level {
        i if i <= 0 => ruzstd::encoding::CompressionLevel::Uncompressed,
        _ => ruzstd::encoding::CompressionLevel::Fastest,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
    let level = level.clamp(1, 22);
    let compressed =
        ruzstd::encoding::compress_to_vec(data.as_slice(), compression_level(level));
    ok_binary(env, &compressed)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match ruzstd::decoding::StreamingDecoder::new(data.as_slice()) {
        Ok(mut decoder) => {
            let mut out = Vec::new();
            match decoder.read_to_end(&mut out) {
                Ok(_) => ok_binary(env, &out),
                Err(_) => err(env, atoms::decompression_failed()),
            }
        }
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
