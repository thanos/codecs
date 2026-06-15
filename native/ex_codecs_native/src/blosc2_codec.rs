use rustler::{Binary, Encoder, Env, Term};

use crate::atoms;
use crate::util::encode_binary;

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

fn bit_shuffle(data: &[u8], typesize: usize) -> Vec<u8> {
    if typesize == 0 || data.is_empty() {
        return data.to_vec();
    }

    let n_elements = data.len() / typesize;
    if n_elements == 0 {
        return data.to_vec();
    }

    let n_full_blocks = n_elements / 8;
    let block_bytes = n_full_blocks * 8 * typesize;
    let mut result = vec![0u8; data.len()];
    let mut out_pos = 0;

    for block in 0..n_full_blocks {
        let block_start = block * 8;
        for byte_idx in 0..typesize {
            for bit_idx in 0..8 {
                let mut acc: u8 = 0;
                for i in 0..8 {
                    let src = data[(block_start + i) * typesize + byte_idx];
                    if src & (1 << (7 - bit_idx)) != 0 {
                        acc |= 1 << (7 - i);
                    }
                }
                result[out_pos] = acc;
                out_pos += 1;
            }
        }
    }

    if block_bytes < data.len() {
        result[block_bytes..data.len()].copy_from_slice(&data[block_bytes..data.len()]);
    }

    result
}

fn bit_unshuffle(data: &[u8], typesize: usize) -> Vec<u8> {
    if typesize == 0 || data.is_empty() {
        return data.to_vec();
    }

    let n_elements = data.len() / typesize;
    if n_elements == 0 {
        return data.to_vec();
    }

    let n_full_blocks = n_elements / 8;
    let block_bytes = n_full_blocks * 8 * typesize;
    let mut result = vec![0u8; data.len()];
    let mut in_pos = 0;

    for block in 0..n_full_blocks {
        let block_start = block * 8;
        for byte_idx in 0..typesize {
            let mut transposed = [0u8; 8];
            for k in 0..8 {
                transposed[k] = data[in_pos];
                in_pos += 1;
            }
            for i in 0..8 {
                let mut byte_val: u8 = 0;
                for bit_idx in 0..8 {
                    if transposed[bit_idx] & (1 << (7 - i)) != 0 {
                        byte_val |= 1 << (7 - bit_idx);
                    }
                }
                result[(block_start + i) * typesize + byte_idx] = byte_val;
            }
        }
    }

    if block_bytes < data.len() {
        result[block_bytes..data.len()].copy_from_slice(&data[block_bytes..data.len()]);
    }

    result
}

fn internal_compress(data: &[u8], cname: u8, clevel: u8) -> Result<Vec<u8>, ()> {
    match cname {
        BLOSC_BLOSCLZ | BLOSC_LZ4 | BLOSC_LZ4HC => Ok(lz4_flex::compress_prepend_size(data)),
        BLOSC_SNAPPY => {
            let mut encoder = snap::raw::Encoder::new();
            encoder.compress_vec(data).map_err(|_| ())
        }
        BLOSC_ZSTD => {
            let level = (clevel as i32).clamp(1, 22);
            zstd::bulk::compress(data, level).map_err(|_| ())
        }
        BLOSC_ZLIB => Ok(lz4_flex::compress_prepend_size(data)),
        _ => Err(()),
    }
}

fn internal_decompress(data: &[u8], cname: u8, _nbytes: usize) -> Result<Vec<u8>, ()> {
    match cname {
        BLOSC_BLOSCLZ | BLOSC_LZ4 | BLOSC_LZ4HC => {
            lz4_flex::decompress_size_prepended(data).map_err(|_| ())
        }
        BLOSC_SNAPPY => {
            let mut decoder = snap::raw::Decoder::new();
            decoder.decompress_vec(data).map_err(|_| ())
        }
        BLOSC_ZSTD => zstd::decode_all(data).map_err(|_| ()),
        BLOSC_ZLIB => {
            lz4_flex::decompress_size_prepended(data).map_err(|_| ())
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
) -> Term<'a> {
    let clevel = clevel.clamp(0, 9) as u8;
    let typesize = typesize.max(1);
    let cname = cname.clamp(0, 5) as u8;
    let shuffle = shuffle.clamp(0, 2) as u8;

    if data.len() > u32::MAX as usize {
        return (atoms::error(), atoms::invalid_data()).encode(env);
    }

    if data.is_empty() {
        let mut header = vec![0u8; BLOSC_MIN_HEADER_LENGTH];
        header[0] = BLOSC2_MAGIC;
        header[1] = BLOSC2_VERSION;
        header[2] = 0x01;
        header[3] = 0;
        header[4..8].copy_from_slice(&0u32.to_le_bytes());
        header[8..12].copy_from_slice(&(BLOSC_MIN_HEADER_LENGTH as u32).to_le_bytes());
        header[12] = cname;
        header[13] = clevel;
        header[14] = BLOSC_NOSHUFFLE;
        header[15] = typesize.max(1) as u8;
        return (atoms::ok(), encode_binary(env, &header)).encode(env);
    }

    let shuffled = match shuffle {
        BLOSC_BYTESHUFFLE => byte_shuffle(data.as_slice(), typesize),
        BLOSC_BITSHUFFLE => bit_shuffle(data.as_slice(), typesize),
        _ => data.as_slice().to_vec(),
    };

    if clevel == 0 {
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

    let compressed = match internal_compress(&shuffled, cname, clevel) {
        Ok(c) => c,
        Err(()) => return (atoms::error(), atoms::compression_failed()).encode(env),
    };

    if compressed.len() >= shuffled.len() {
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
    output[2] = 0x00;
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
        if BLOSC_MIN_HEADER_LENGTH + nbytes > data.len() {
            return (atoms::error(), atoms::invalid_data()).encode(env);
        }
        let result = data[BLOSC_MIN_HEADER_LENGTH..BLOSC_MIN_HEADER_LENGTH + nbytes].to_vec();
        return (atoms::ok(), encode_binary(env, &result)).encode(env);
    }

    let payload = &data[BLOSC_MIN_HEADER_LENGTH..cbytes];
    let decompressed = match internal_decompress(payload, cname, nbytes) {
        Ok(d) => d,
        Err(()) => return (atoms::error(), atoms::decompression_failed()).encode(env),
    };

    let result = match shuffle {
        BLOSC_BYTESHUFFLE => byte_unshuffle(&decompressed, typesize),
        BLOSC_BITSHUFFLE => bit_unshuffle(&decompressed, typesize),
        _ => decompressed,
    };

    (atoms::ok(), encode_binary(env, &result)).encode(env)
}