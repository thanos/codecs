use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

use crate::atoms;

/// Copy bytes into an Erlang binary term.
///
/// Returns `Ok(binary_term)` or `Err` when allocation fails so callers never
/// nest `{:ok, {:error, _}}`.
pub fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Result<Term<'a>, ()> {
    match OwnedBinary::new(data.len()) {
        Some(mut owned) => {
            owned.as_mut_slice().copy_from_slice(data);
            Ok(Binary::from_owned(owned, env).encode(env))
        }
        None => Err(()),
    }
}

/// Encode `{:ok, binary}` or `{:error, reason}` for NIF returns.
pub fn ok_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    match encode_binary(env, data) {
        Ok(bin) => (atoms::ok(), bin).encode(env),
        Err(()) => (atoms::error(), atoms::invalid_data()).encode(env),
    }
}

pub fn err<'a>(env: Env<'a>, reason: rustler::types::atom::Atom) -> Term<'a> {
    (atoms::error(), reason).encode(env)
}
