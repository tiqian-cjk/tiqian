//! Worker spread for the batch entries (ADR 0050). The batch entries own
//! their item loops; this module spreads the items over scoped threads while
//! keeping the three guarantees the sequential loop had: results land in
//! input order, the reported error is the one of the lowest failing index,
//! and a worker panic leaves the scope instead of vanishing. The knob is
//! `TIQIAN_PRECOMPUTE_THREADS`; `1` selects the plain sequential loop.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, PoisonError};

/// `TIQIAN_PRECOMPUTE_THREADS`, defaulting to the machine's available
/// parallelism. A missing or malformed value reads as the default: the knob
/// only tunes worker count, and the batch outputs stay identical for every
/// value, so the fallback cannot change what a call produces.
pub fn worker_count() -> usize {
    match std::env::var("TIQIAN_PRECOMPUTE_THREADS") {
        Ok(value) => parse_worker_count(&value).unwrap_or_else(default_worker_count),
        Err(_) => default_worker_count(),
    }
}

/// Parses one `TIQIAN_PRECOMPUTE_THREADS` value; whole numbers from one up
/// are valid, anything else falls back to the default.
fn parse_worker_count(value: &str) -> Option<usize> {
    let trimmed = value.trim();
    if trimmed.starts_with('+') {
        return None;
    }
    let parsed: usize = trimmed.parse().ok()?;
    (parsed >= 1).then_some(parsed)
}

fn default_worker_count() -> usize {
    std::thread::available_parallelism()
        .map(|count| count.get())
        .unwrap_or(1)
}

/// Recovers a mutex guard after a panic in another thread: the protected
/// slots stay structurally valid, so the recovered guard keeps every caller
/// total. Mirrors the neon registry helper.
pub(crate) fn recover<T>(lock: Result<T, PoisonError<T>>) -> T {
    lock.unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Runs `work` over `0..len` on at most `workers` scoped threads and
/// collects the values in input order. The first error by index wins, the
/// sequential loop's `?` order; items after an error still run to keep every
/// slot filled, which costs work only on the error path because a failed
/// batch discards its entries anyway. A panic in `work` propagates through
/// the scope after the workers join.
pub fn indexed_collect<T, E>(
    len: usize,
    workers: usize,
    work: impl Fn(usize) -> Result<T, E> + Sync,
) -> Result<Vec<T>, E>
where
    T: Send,
    E: Send,
{
    let mut slots: Vec<Mutex<Option<Result<T, E>>>> = Vec::with_capacity(len);
    for _ in 0..len {
        slots.push(Mutex::new(None));
    }
    if workers > 1 && len > 1 {
        let next = AtomicUsize::new(0);
        let slots_ref = &slots;
        // The references keep `work` and the counter shared: `&F` crosses
        // into the workers when `F` is `Sync`, and no closure owns `F`.
        let work_ref = &work;
        let next_ref = &next;
        std::thread::scope(|scope| {
            for _ in 0..workers.min(len) {
                scope.spawn(move || loop {
                    let index = next_ref.fetch_add(1, Ordering::Relaxed);
                    if index >= len {
                        break;
                    }
                    let value = work_ref(index);
                    *recover(slots_ref[index].lock()) = Some(value);
                });
            }
        });
    } else {
        for (index, slot) in slots.iter().enumerate() {
            *recover(slot.lock()) = Some(work(index));
        }
    }
    let mut values: Vec<T> = Vec::with_capacity(len);
    for slot in slots {
        // Every index below `len` is claimed and filled before its worker
        // exits, so the empty arm is dead; it ends the scan instead of
        // inventing a value.
        let Some(value) = recover(slot.into_inner()) else {
            break;
        };
        match value {
            Ok(item) => values.push(item),
            Err(error) => return Err(error),
        }
    }
    Ok(values)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worker_count_values_parse_with_padding() {
        assert_eq!(parse_worker_count("1"), Some(1));
        assert_eq!(parse_worker_count(" 4 "), Some(4));
        assert_eq!(
            parse_worker_count(&format!("{}", usize::MAX)),
            Some(usize::MAX)
        );
    }

    #[test]
    fn worker_count_rejects_malformed_values() {
        assert_eq!(parse_worker_count(""), None);
        assert_eq!(parse_worker_count("0"), None);
        assert_eq!(parse_worker_count("-2"), None);
        assert_eq!(parse_worker_count("+4"), None);
        assert_eq!(parse_worker_count("four"), None);
        assert_eq!(parse_worker_count("2.5"), None);
    }

    #[test]
    fn indexed_collect_keeps_input_order_across_workers() {
        let values =
            indexed_collect(50, 4, |index| Ok::<usize, ()>(index * 2)).expect("all items succeed");
        let expected: Vec<usize> = (0..50).map(|index| index * 2).collect();
        assert_eq!(values, expected);
    }

    #[test]
    fn indexed_collect_reports_the_lowest_failing_index() {
        let failure = indexed_collect(20, 4, |index| {
            if index == 3 || index == 7 {
                Err(index)
            } else {
                Ok(index)
            }
        })
        .expect_err("the batch fails");
        assert_eq!(failure, 3);
    }

    #[test]
    fn indexed_collect_single_worker_matches_the_sequential_loop() {
        let sequential: Vec<usize> = (0..10).map(|index| index + 1).collect();
        let values =
            indexed_collect(10, 1, |index| Ok::<usize, ()>(index + 1)).expect("all items succeed");
        assert_eq!(values, sequential);
    }

    #[test]
    fn indexed_collect_accepts_empty_batches() {
        let values: Vec<usize> =
            indexed_collect(0, 4, |index| Ok::<usize, ()>(index)).expect("empty succeeds");
        assert!(values.is_empty());
    }

    #[test]
    // The scope re-panics with its own wrapper message instead of resuming
    // the worker's payload, so only the propagation itself is asserted.
    #[should_panic]
    fn indexed_collect_propagates_worker_panics() {
        indexed_collect(10, 3, |index| {
            if index == 2 {
                panic!("worker panic surfaces");
            }
            Ok::<usize, ()>(index)
        })
        .expect("the panic leaves the scope first");
    }
}
