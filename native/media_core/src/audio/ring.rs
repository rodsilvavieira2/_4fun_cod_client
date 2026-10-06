//! Ring buffers bounded (§9.2): capacidade fixa, semântica de drop
//! explícita, high-water mark e contadores. Modelo single-owner por
//! relação produtor/consumidor; SPSC lock-free real entra com o backend.

use std::collections::VecDeque;

/// Política de overflow: descarta o mais antigo (voz: prefere o novo) ou
/// recusa o novo (comandos: nunca perder o atual).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OverflowPolicy {
    DropOldest,
    DropNewest,
}

#[derive(Debug)]
pub struct BoundedQueue<T> {
    queue: VecDeque<T>,
    capacity_blocks: usize,
    dropped: u64,
    high_water_mark: usize,
    policy: OverflowPolicy,
}

impl<T> BoundedQueue<T> {
    pub fn new(capacity_blocks: usize, policy: OverflowPolicy) -> Self {
        assert!(capacity_blocks > 0, "capacity must be > 0");
        Self {
            queue: VecDeque::with_capacity(capacity_blocks),
            capacity_blocks,
            dropped: 0,
            high_water_mark: 0,
            policy,
        }
    }

    /// Enfileira; retorna `true` se o item foi aceito.
    pub fn push(&mut self, item: T) -> bool {
        if self.queue.len() >= self.capacity_blocks {
            self.dropped += 1;
            match self.policy {
                OverflowPolicy::DropOldest => {
                    self.queue.pop_front();
                    self.queue.push_back(item);
                    self.note_high_water();
                    true
                }
                OverflowPolicy::DropNewest => false,
            }
        } else {
            self.queue.push_back(item);
            self.note_high_water();
            true
        }
    }

    pub fn pop(&mut self) -> Option<T> {
        self.queue.pop_front()
    }

    /// Remove backlog antigo além de `keep_newest` (reconexão: nunca
    /// acumular voz velha — §9.2).
    pub fn drain_backlog(&mut self, keep_newest: usize) -> usize {
        let mut removed = 0;
        while self.queue.len() > keep_newest {
            self.queue.pop_front();
            self.dropped += 1;
            removed += 1;
        }
        removed
    }

    pub fn len(&self) -> usize {
        self.queue.len()
    }

    pub fn is_empty(&self) -> bool {
        self.queue.is_empty()
    }

    pub fn capacity_blocks(&self) -> usize {
        self.capacity_blocks
    }

    pub fn dropped(&self) -> u64 {
        self.dropped
    }

    pub fn high_water_mark(&self) -> usize {
        self.high_water_mark
    }

    fn note_high_water(&mut self) {
        self.high_water_mark = self.high_water_mark.max(self.queue.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drop_oldest_prefers_new_audio() {
        let mut q = BoundedQueue::new(3, OverflowPolicy::DropOldest);
        for i in 0..5 {
            assert!(q.push(i));
        }
        assert_eq!(q.dropped(), 2);
        assert_eq!(q.pop(), Some(2));
        assert_eq!(q.pop(), Some(3));
        assert_eq!(q.pop(), Some(4));
    }

    #[test]
    fn drop_newest_never_loses_current_command() {
        let mut q = BoundedQueue::new(2, OverflowPolicy::DropNewest);
        assert!(q.push("a"));
        assert!(q.push("b"));
        assert!(!q.push("c"));
        assert_eq!(q.dropped(), 1);
        assert_eq!(q.pop(), Some("a"));
    }

    #[test]
    fn drain_backlog_discards_stale_voice() {
        let mut q = BoundedQueue::new(6, OverflowPolicy::DropOldest);
        for i in 0..6 {
            q.push(i);
        }
        assert_eq!(q.drain_backlog(1), 5);
        assert_eq!(q.len(), 1);
        assert_eq!(q.pop(), Some(5));
    }

    #[test]
    fn high_water_mark_tracks_peak() {
        let mut q = BoundedQueue::new(6, OverflowPolicy::DropOldest);
        q.push(1);
        q.push(2);
        q.pop();
        q.push(3);
        q.push(4);
        assert_eq!(q.high_water_mark(), 3);
    }
}
