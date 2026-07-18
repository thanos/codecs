use rustler::{Binary, Env, Term};
use std::io::Read;

use crate::atoms;
use crate::util::{err, ok_binary, output_within_limit};

use structured_zstd::encoding::{compress_to_vec, CompressionLevel};

pub fn version() -> String {
    "structured-zstd-0.0.48".to_string()
}

fn compression_level(level: i32) -> CompressionLevel {
    // Pure-Rust encoder with numeric levels 1..=22 (no C libzstd).
    CompressionLevel::from_level(level.clamp(1, 22))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
    let compressed = compress_to_vec(data.as_slice(), compression_level(level));
    ok_binary(env, &compressed)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_decompress<'a>(env: Env<'a>, data: Binary, max_output_size: u64) -> Term<'a> {
    let mut remaining = data.as_slice();
    match structured_zstd::decoding::StreamingDecoder::new(&mut remaining) {
        Ok(mut decoder) => {
            let mut out = Vec::new();
            let mut buf = [0u8; 8192];
            loop {
                match decoder.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if !output_within_limit(out.len().saturating_add(n), max_output_size) {
                            return err(env, atoms::output_limit_exceeded());
                        }
                        out.extend_from_slice(&buf[..n]);
                    }
                    Err(_) => return err(env, atoms::decompression_failed()),
                }
            }
            // Single-frame API: reject concatenated frames / trailing garbage.
            if !remaining.is_empty() {
                return err(env, atoms::decompression_failed());
            }
            ok_binary(env, &out)
        }
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
