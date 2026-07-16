use rustler::{Binary, Env, Term};
use std::io::{Read, Write};

use crate::atoms;
use crate::util::{err, ok_binary, output_within_limit};

pub fn version() -> String {
    "bzip2-0.6/libbz2-rs".to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn bzip2_compress<'a>(env: Env<'a>, data: Binary, block_size: u32) -> Term<'a> {
    let block_size = block_size.clamp(1, 9);

    let result: Result<Vec<u8>, std::io::Error> = (|| {
        let mut compressed = Vec::with_capacity(data.len() / 2);
        {
            let mut writer =
                bzip2::write::BzEncoder::new(&mut compressed, bzip2::Compression::new(block_size));
            writer.write_all(data.as_slice())?;
            writer.finish()?;
        }
        Ok(compressed)
    })();

    match result {
        Ok(compressed) => ok_binary(env, &compressed),
        Err(_) => err(env, atoms::compression_failed()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn bzip2_decompress<'a>(env: Env<'a>, data: Binary, max_output_size: u64) -> Term<'a> {
    let result: Result<Vec<u8>, LimitError> = (|| {
        let mut decompressed = Vec::with_capacity(data.len().saturating_mul(4).min(64 * 1024));
        let mut reader = bzip2::read::BzDecoder::new(data.as_slice());
        let mut buf = [0u8; 8192];
        loop {
            let n = reader.read(&mut buf).map_err(|_| LimitError::Io)?;
            if n == 0 {
                break;
            }
            if !output_within_limit(decompressed.len().saturating_add(n), max_output_size) {
                return Err(LimitError::Limit);
            }
            decompressed.extend_from_slice(&buf[..n]);
        }
        Ok(decompressed)
    })();

    match result {
        Ok(decompressed) => ok_binary(env, &decompressed),
        Err(LimitError::Limit) => err(env, atoms::output_limit_exceeded()),
        Err(LimitError::Io) => err(env, atoms::decompression_failed()),
    }
}

enum LimitError {
    Limit,
    Io,
}
