use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

use crate::atoms;

pub fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    match OwnedBinary::new(data.len()) {
        Some(mut owned) => {
            owned.as_mut_slice().copy_from_slice(data);
            Binary::from_owned(owned, env).encode(env)
        }
        None => (atoms::error(), atoms::invalid_data()).encode(env),
    }
}