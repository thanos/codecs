use rustler::{Binary, Env, Term};
use std::io::{Read, Write};

use crate::atoms;
use crate::util::{err, ok_binary};

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
pub fn bzip2_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let result: Result<Vec<u8>, std::io::Error> = (|| {
        let mut decompressed = Vec::with_capacity(data.len() * 4);
        {
            let mut reader = bzip2::read::BzDecoder::new(data.as_slice());
            reader.read_to_end(&mut decompressed)?;
        }
        Ok(decompressed)
    })();

    match result {
        Ok(decompressed) => ok_binary(env, &decompressed),
        Err(_) => err(env, atoms::decompression_failed()),
    }
}
