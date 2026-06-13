use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

use crate::atoms;

fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut owned = OwnedBinary::new(data.len()).expect("allocation failed");
    owned.as_mut_slice().copy_from_slice(data);
    Binary::from_owned(owned, env).encode(env)
}

pub fn version() -> String {
    "2.x-pure-rust".to_string()
}

const BLOSC2_MAGIC: u8 = 0x2c;
const BLOSC2_VERSION: u8 = 2;
const BLOSC_MIN_HEADER_LENGTH: usize = 16;

const BLOSC_BLOSCLZ: u8 = 0;
const BLOSC_LZ4: u8 = 1;
const BLOSC_LZ4HC: u8 = 2;
const BLOSC_SNAPPY: u8 = 3;
const BLOSC_ZLIB: u8 = 4;
const BLOSC_ZSTD: u8 = 5;

const BLOSC_NOSHUFFLE: u8 = 0;
const BLOSC_BYTESHUFFLE: u8 = 1;
const BLOSC_BITSHUFFLE: u8 = 2;

fn byte_shuffle(data: &[u8], typesize: usize) -> Vec<u8> {
    if typesize <= 1 || data.len() < typesize {
        return data.to_vec();
    }

    let n_elements = data.len() / typesize;
    let mut result = vec![0u8; data.len()];

    for i in 0..n_elements {
        for j in 0..typesize {
            result[j * n_elements + i] = data[i * typesize + j];
        }
    }

    let offset = n_elements * typesize;
    if offset < data.len() {
        result[offset..].copy_from_slice(&data[offset..]);
    }

    result
}

fn byte_unshuffle(data: &[u8], typesize: usize) -> Vec<u8> {
    if typesize <= 1 || data.len() < typesize {
        return data.to_vec();
    }

    let n_elements = data.len() / typesize;
    let mut result = vec![0u8; data.len()];

    for i in 0..n_elements {
        for j in 0..typesize {
            result[i * typesize + j] = data[j * n_elements + i];
        }
    }

    let offset = n_elements * typesize;
    if offset < data.len() {
        result[offset..].copy_from_slice(&data[offset..]);
    }

    result
}

fn internal_compress(data: &[u8], cname: u8, clevel: u8) -> Result<Vec<u8>, ()> {
    match cname {
        BLOSC_BLOSCLZ | BLOSC_LZ4 | BLOSC_LZ4HC => Ok(lz4_flex::compress(data)),
        BLOSC_SNAPPY => {
            let mut encoder = snap::raw::Encoder::new();
            encoder.compress_vec(data).map_err(|_| ())
        }
        BLOSC_ZSTD => {
            let level = (clevel as i32).clamp(1, 22);
            zstd::bulk::compress(data, level).map_err(|_| ())
        }
        BLOSC_ZLIB => Ok(lz4_flex::compress(data)),
        _ => Err(()),
    }
}

fn internal_decompress(data: &[u8], cname: u8) -> Result<Vec<u8>, ()> {
    match cname {
        BLOSC_BLOSCLZ | BLOSC_LZ4 | BLOSC_LZ4HC => {
            let max_size = data.len() * 10;
            lz4_flex::decompress(data, max_size).map_err(|_| ())
        }
        BLOSC_SNAPPY => {
            let mut decoder = snap::raw::Decoder::new();
            decoder.decompress_vec(data).map_err(|_| ())
        }
        BLOSC_ZSTD => zstd::decode_all(data).map_err(|_| ()),
        BLOSC_ZLIB => {
            let max_size = data.len() * 10;
            lz4_flex::decompress(data, max_size).map_err(|_| ())
        }
        _ => Err(()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn blosc2_compress<'a>(
    env: Env<'a>,
    data: Binary,
    cname: i64,
    clevel: i64,
    shuffle: i64,
    typesize: usize,
    _blocksize: usize,
    _numthreads: i64,
) -> Term<'a> {
    let clevel = clevel.clamp(0, 9) as u8;
    let typesize = typesize.max(1);
    let cname = cname.clamp(0, 5) as u8;
    let shuffle = shuffle.clamp(0, 2) as u8;

    if data.is_empty() {
        let mut header = vec![0u8; BLOSC_MIN_HEADER_LENGTH];
        header[0] = BLOSC2_MAGIC;
        header[1] = BLOSC2_VERSION;
        header[2] = 0;
        header[3] = 0;
        header[4..8].copy_from_slice(&0u32.to_le_bytes());
        header[8..12].copy_from_slice(&(BLOSC_MIN_HEADER_LENGTH as u32).to_le_bytes());
        header[12] = cname;
        header[13] = clevel;
        header[14] = shuffle;
        header[15] = typesize.max(1) as u8;
        return (atoms::ok(), encode_binary(env, &header)).encode(env);
    }

    let shuffled = match shuffle {
        BLOSC_BYTESHUFFLE => byte_shuffle(data.as_slice(), typesize),
        BLOSC_BITSHUFFLE => byte_shuffle(data.as_slice(), typesize),
        _ => data.as_slice().to_vec(),
    };

    let compressed = match internal_compress(&shuffled, cname, clevel) {
        Ok(c) => c,
        Err(()) => return (atoms::error(), atoms::compression_failed()).encode(env),
    };

    if compressed.len() >= shuffled.len() && clevel > 0 {
        let payload = data.as_slice();
        let total_len = BLOSC_MIN_HEADER_LENGTH + payload.len();
        let mut output = vec![0u8; total_len];
        output[0] = BLOSC2_MAGIC;
        output[1] = BLOSC2_VERSION;
        output[2] = 0x01;
        output[3] = 0;
        output[4..8].copy_from_slice(&(payload.len() as u32).to_le_bytes());
        output[8..12].copy_from_slice(&(total_len as u32).to_le_bytes());
        output[12] = 0;
        output[13] = 0;
        output[14] = BLOSC_NOSHUFFLE;
        output[15] = typesize.max(1) as u8;
        output[BLOSC_MIN_HEADER_LENGTH..].copy_from_slice(payload);
        return (atoms::ok(), encode_binary(env, &output)).encode(env);
    }

    let total_len = BLOSC_MIN_HEADER_LENGTH + compressed.len();
    let mut output = vec![0u8; total_len];
    output[0] = BLOSC2_MAGIC;
    output[1] = BLOSC2_VERSION;
    output[2] = shuffle;
    output[3] = 0;
    output[4..8].copy_from_slice(&(data.len() as u32).to_le_bytes());
    output[8..12].copy_from_slice(&(total_len as u32).to_le_bytes());
    output[12] = cname;
    output[13] = clevel;
    output[14] = shuffle;
    output[15] = typesize.max(1) as u8;
    output[BLOSC_MIN_HEADER_LENGTH..].copy_from_slice(&compressed);

    (atoms::ok(), encode_binary(env, &output)).encode(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn blosc2_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    if data.len() < BLOSC_MIN_HEADER_LENGTH {
        return (atoms::error(), atoms::invalid_data()).encode(env);
    }

    if data[0] != BLOSC2_MAGIC {
        return (atoms::error(), atoms::invalid_data()).encode(env);
    }

    let nbytes = u32::from_le_bytes([data[4], data[5], data[6], data[7]]) as usize;
    let cbytes = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;
    let flags = data[2];
    let cname = data[12];
    let _clevel = data[13];
    let shuffle = data[14];
    let typesize = data[15] as usize;

    if cbytes > data.len() {
        return (atoms::error(), atoms::invalid_data()).encode(env);
    }

    if flags & 0x01 != 0 {
        let result = data[BLOSC_MIN_HEADER_LENGTH..BLOSC_MIN_HEADER_LENGTH + nbytes].to_vec();
        return (atoms::ok(), encode_binary(env, &result)).encode(env);
    }

    let payload = &data[BLOSC_MIN_HEADER_LENGTH..cbytes];
    let decompressed = match internal_decompress(payload, cname) {
        Ok(d) => d,
        Err(()) => return (atoms::error(), atoms::decompression_failed()).encode(env),
    };

    let result = match shuffle {
        BLOSC_BYTESHUFFLE => byte_unshuffle(&decompressed, typesize),
        BLOSC_BITSHUFFLE => byte_unshuffle(&decompressed, typesize),
        _ => decompressed,
    };

    (atoms::ok(), encode_binary(env, &result)).encode(env)
}