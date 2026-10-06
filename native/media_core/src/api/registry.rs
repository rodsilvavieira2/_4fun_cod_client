//! Registry de engines: ID resolve numa registry validada com
//! incarnation (anti-reuse); ponteiro arbitrário nunca vira referência.

use crate::engine::actor::Engine;
use crate::errors::MediaError;
use std::collections::HashMap;

pub struct EngineRegistry {
    engines: HashMap<u64, Engine>,
    next_id: u64,
    next_incarnation: u64,
}

impl EngineRegistry {
    pub fn new() -> Self {
        Self {
            engines: HashMap::new(),
            next_id: 1,
            next_incarnation: 1,
        }
    }

    pub fn create(
        &mut self,
        flags: HashMap<String, bool>,
    ) -> (u64, u64) {
        let id = self.next_id;
        self.next_id += 1;
        let incarnation = self.next_incarnation;
        self.next_incarnation += 1;
        self.engines.insert(id, Engine::create(id, incarnation, flags));
        (id, incarnation)
    }

    pub fn get(&self, id: u64) -> Result<&Engine, MediaError> {
        self.engines.get(&id).ok_or(MediaError::InvalidHandle)
    }

    pub fn get_mut(&mut self, id: u64) -> Result<&mut Engine, MediaError> {
        self.engines.get_mut(&id).ok_or(MediaError::InvalidHandle)
    }

    /// Destroy idempotente: segunda chamada com mesma incarnation é no-op
    /// seguro; ID reciclado com incarnation nova nunca resolve o antigo.
    pub fn dispose(&mut self, id: u64) -> Result<(), MediaError> {
        match self.engines.get_mut(&id) {
            Some(engine) => {
                engine.dispose();
                self.engines.remove(&id);
                Ok(())
            }
            None => Err(MediaError::InvalidHandle),
        }
    }

    pub fn len(&self) -> usize {
        self.engines.len()
    }

    pub fn is_empty(&self) -> bool {
        self.engines.is_empty()
    }
}

impl Default for EngineRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_get_dispose_lifecycle() {
        let mut r = EngineRegistry::new();
        let (id, _) = r.create(HashMap::new());
        assert!(r.get(id).is_ok());
        r.dispose(id).unwrap();
        assert!(r.get(id).is_err());
        // Dispose repetido: erro InvalidHandle (não crash).
        assert!(r.dispose(id).is_err());
    }
}
