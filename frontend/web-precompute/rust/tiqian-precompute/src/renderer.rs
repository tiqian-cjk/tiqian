//! The batch renderer pool (ADR 0052): one resident worker set behind one
//! global queue. Jobs enter as content-keyed compute tasks; cache hits never
//! queue, they resolve in the memory tier before enqueue. The waiting egress
//! blocks on a per-job condvar, so a synchronous caller parks its thread
//! without spinning and without needing the JS event loop.
//!
//! Workers never call back into the host and never enqueue nested work, so a
//! blocked submitter cannot be required by any worker: the pool cannot
//! deadlock through its own queue. Synchronous submissions push to the queue
//! front, ahead of background and prefilled work.

use std::any::Any;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};

use tiqian::NamedError;

/// Queue depth backpressure: submissions wait once this many jobs are queued.
/// Waiting submitters hold no locks, so workers keep draining.
const QUEUE_MAX_DEPTH: usize = 1024;

type Task = Box<dyn FnOnce() -> Result<(), NamedError> + Send>;

/// The dedup identity of a job: the submitting precomputer's owner id plus the
/// store key. Two precomputers over the same context derive equal store keys
/// but hold separate cache stores, and the write-through lands in the
/// submitter's store, so dedup never crosses instances.
pub type JobKey = (u64, [u8; 32]);

struct QueuedJob {
    job: Arc<RenderJob>,
    key: Option<JobKey>,
    task: Task,
}

struct PoolState {
    queue: VecDeque<QueuedJob>,
    /// In-flight jobs by dedup identity; a finished job leaves the map, its
    /// result lives in the cache store.
    keyed: HashMap<JobKey, Arc<RenderJob>>,
}

enum JobState {
    Queued,
    Running,
    Done,
    Failed(NamedError),
    Panicked(Box<dyn Any + Send>),
    PanicConsumed,
}

/// One queued or running unit of work plus its completion signal.
pub struct RenderJob {
    state: Mutex<JobState>,
    signal: Condvar,
}

impl RenderJob {
    fn new() -> Self {
        RenderJob {
            state: Mutex::new(JobState::Queued),
            signal: Condvar::new(),
        }
    }
}

/// The resident pool. The first use spawns the workers, which live for the
/// process; there is no shutdown path because the pool is process-global.
pub struct BatchPool {
    state: Mutex<PoolState>,
    ready: Condvar,
    space: Condvar,
    completed: AtomicU64,
    worker_count: usize,
}

static POOL: OnceLock<BatchPool> = OnceLock::new();

/// Hands out per-precomputer owner ids for job dedup.
pub fn next_job_owner() -> u64 {
    static NEXT_OWNER: AtomicU64 = AtomicU64::new(1);
    NEXT_OWNER.fetch_add(1, Ordering::Relaxed)
}

/// The process-global pool. Worker count follows
/// `TIQIAN_PRECOMPUTE_THREADS`, the same variable as the low-level batch
/// lanes.
pub fn global_pool() -> &'static BatchPool {
    POOL.get_or_init(|| {
        let worker_count = crate::parallel::worker_count();
        let pool = BatchPool {
            state: Mutex::new(PoolState {
                queue: VecDeque::new(),
                keyed: HashMap::new(),
            }),
            ready: Condvar::new(),
            space: Condvar::new(),
            completed: AtomicU64::new(0),
            worker_count,
        };
        for index in 0..worker_count {
            std::thread::Builder::new()
                .name(format!("tiqian-render-{index}"))
                .spawn(|| pool_worker_loop())
                .ok();
        }
        pool
    })
}

fn pool_worker_loop() {
    loop {
        let queued = {
            let mut state = crate::parallel::recover(global_pool().state.lock());
            loop {
                match state.queue.pop_front() {
                    Some(queued) => {
                        global_pool().space.notify_all();
                        break queued;
                    }
                    None => {
                        state = crate::parallel::recover(global_pool().ready.wait(state));
                    }
                }
            }
        };
        let QueuedJob { job, key, task } = queued;
        {
            let mut state = crate::parallel::recover(job.state.lock());
            if matches!(&*state, JobState::Queued) {
                *state = JobState::Running;
            }
        }
        let outcome = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(task)) {
            Ok(Ok(())) => JobState::Done,
            Ok(Err(error)) => JobState::Failed(error),
            Err(payload) => JobState::Panicked(payload),
        };
        {
            let mut state = crate::parallel::recover(job.state.lock());
            *state = outcome;
        }
        job.signal.notify_all();
        // The in-flight entry leaves the map at completion, so submitters
        // during execution attach to this job instead of queueing duplicate
        // work; a dedup attach after completion reads the outcome and moves
        // on without parking.
        if let Some(key) = key {
            let mut state = crate::parallel::recover(global_pool().state.lock());
            if state
                .keyed
                .get(&key)
                .is_some_and(|current| Arc::ptr_eq(current, &job))
            {
                state.keyed.remove(&key);
            }
        }
        global_pool().completed.fetch_add(1, Ordering::Relaxed);
    }
}

/// Where an enqueued job waits inside the queue: the front serves
/// synchronous submitters first, the back serves background and prefilled
/// work.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum QueuePosition {
    Front,
    Back,
}

impl BatchPool {
    /// Enqueues one job under one lock hold: a key that is already in flight
    /// returns the existing job instead of queueing duplicate work, so the
    /// second submitter waits on the first submission's completion.
    pub fn enqueue(
        &self,
        key: Option<JobKey>,
        position: QueuePosition,
        task: Task,
    ) -> Result<Arc<RenderJob>, NamedError> {
        let mut state = crate::parallel::recover(self.state.lock());
        if let Some(key) = key {
            if let Some(existing) = state.keyed.get(&key) {
                let existing = existing.clone();
                drop(state);
                return Ok(existing);
            }
        }
        // Backpressure: wait while the queue is at depth. The condvar wait
        // releases the lock, so workers keep draining.
        while state.queue.len() >= QUEUE_MAX_DEPTH {
            state = crate::parallel::recover(self.space.wait(state));
        }
        let job = Arc::new(RenderJob::new());
        let queued = QueuedJob {
            job: job.clone(),
            key,
            task,
        };
        match position {
            QueuePosition::Front => state.queue.push_front(queued),
            QueuePosition::Back => state.queue.push_back(queued),
        }
        if let Some(key) = key {
            state.keyed.insert(key, job.clone());
        }
        drop(state);
        self.ready.notify_all();
        Ok(job)
    }

    pub fn queue_depth(&self) -> usize {
        crate::parallel::recover(self.state.lock()).queue.len()
    }

    pub fn worker_count(&self) -> usize {
        self.worker_count
    }

    pub fn jobs_completed(&self) -> u64 {
        self.completed.load(Ordering::Relaxed)
    }
}

/// Waits for a job to finish. A failed job propagates its named error; a
/// panicked job resumes the panic in the first waiter and reports the same
/// named issue to any later waiter.
pub fn wait_job(job: &RenderJob) -> Result<(), NamedError> {
    let mut state = crate::parallel::recover(job.state.lock());
    loop {
        match &mut *state {
            JobState::Queued | JobState::Running => {
                state = crate::parallel::recover(job.signal.wait(state));
            }
            JobState::Done => return Ok(()),
            JobState::Failed(error) => {
                let error = error.clone();
                return Err(error);
            }
            JobState::Panicked(_) => {
                let payload = std::mem::replace(&mut *state, JobState::PanicConsumed);
                drop(state);
                if let JobState::Panicked(payload) = payload {
                    std::panic::resume_unwind(payload);
                }
                return Err(NamedError("RenderJobPanicked".to_string()));
            }
            JobState::PanicConsumed => {
                return Err(NamedError("RenderJobPanicked".to_string()));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    #[test]
    fn jobs_run_and_signal_completion() {
        let pool = global_pool();
        let counter = Arc::new(AtomicUsize::new(0));
        let task_counter = counter.clone();
        let job = pool
            .enqueue(
                None,
                QueuePosition::Back,
                Box::new(move || {
                    task_counter.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                }),
            )
            .expect("enqueue succeeds");
        wait_job(&job).expect("job succeeds");
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn keyed_jobs_deduplicate_in_flight_work() {
        let pool = global_pool();
        let key: JobKey = (1, [11u8; 32]);
        let runs = Arc::new(AtomicUsize::new(0));
        let task_runs = runs.clone();
        let first = pool
            .enqueue(
                Some(key),
                QueuePosition::Front,
                Box::new(move || {
                    std::thread::sleep(std::time::Duration::from_millis(50));
                    task_runs.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                }),
            )
            .expect("enqueue succeeds");
        let second = pool
            .enqueue(
                Some(key),
                QueuePosition::Front,
                Box::new(move || {
                    unreachable!("the deduplicated task never runs");
                }),
            )
            .expect("enqueue succeeds");
        assert!(Arc::ptr_eq(&first, &second));
        wait_job(&second).expect("job succeeds");
        assert_eq!(runs.load(Ordering::SeqCst), 1);
        // The key left the in-flight map: a fresh submission queues fresh
        // work.
        let third = pool
            .enqueue(Some(key), QueuePosition::Front, Box::new(|| Ok(())))
            .expect("enqueue succeeds");
        assert!(!Arc::ptr_eq(&first, &third));
        wait_job(&third).expect("job succeeds");
    }

    #[test]
    fn equal_store_keys_under_different_owners_both_run() {
        // Dedup never crosses precomputer instances: the write-through lands
        // in the submitter's cache store, so an attach across owners would
        // leave the second submitter reading its own store as a miss.
        let pool = global_pool();
        let runs = Arc::new(AtomicUsize::new(0));
        let first_runs = runs.clone();
        let second_runs = runs.clone();
        let first = pool
            .enqueue(
                Some((1, [4u8; 32])),
                QueuePosition::Front,
                Box::new(move || {
                    std::thread::sleep(std::time::Duration::from_millis(50));
                    first_runs.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                }),
            )
            .expect("enqueue succeeds");
        let second = pool
            .enqueue(
                Some((2, [4u8; 32])),
                QueuePosition::Front,
                Box::new(move || {
                    second_runs.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                }),
            )
            .expect("enqueue succeeds");
        assert!(!Arc::ptr_eq(&first, &second));
        wait_job(&first).expect("job succeeds");
        wait_job(&second).expect("job succeeds");
        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn failed_jobs_report_their_named_error() {
        let pool = global_pool();
        let job = pool
            .enqueue(
                None,
                QueuePosition::Back,
                Box::new(|| Err(NamedError("TestFailure".to_string()))),
            )
            .expect("enqueue succeeds");
        let error = wait_job(&job).expect_err("job fails");
        assert_eq!(error.0, "TestFailure");
    }

    #[test]
    fn panicked_jobs_resume_the_panic_in_the_waiter() {
        let pool = global_pool();
        let job = pool
            .enqueue(
                None,
                QueuePosition::Back,
                Box::new(|| {
                    panic!("worker panic surfaces in the waiter");
                }),
            )
            .expect("enqueue succeeds");
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = wait_job(&job);
        }));
        assert!(result.is_err());
        // A later waiter receives the named issue instead of the payload.
        let error = wait_job(&job).expect_err("job reports the panic");
        assert_eq!(error.0, "RenderJobPanicked");
    }
}
