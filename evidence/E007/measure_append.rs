
// TEMPORARY (not committed): peak-heap and time comparison of `verify` and `verify_stored`
mod e007_measure {
  use core::sync::atomic::{AtomicUsize, Ordering};
  use std::alloc::{GlobalAlloc, Layout, System};

  struct Counting;
  static CURRENT: AtomicUsize = AtomicUsize::new(0);
  static PEAK: AtomicUsize = AtomicUsize::new(0);

  unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
      let ptr = unsafe { System.alloc(layout) };
      if !ptr.is_null() {
        let now = CURRENT.fetch_add(layout.size(), Ordering::Relaxed) + layout.size();
        PEAK.fetch_max(now, Ordering::Relaxed);
      }
      ptr
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
      unsafe { System.dealloc(ptr, layout) };
      CURRENT.fetch_sub(layout.size(), Ordering::Relaxed);
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
      let new = unsafe { System.realloc(ptr, layout, new_size) };
      if !new.is_null() {
        if new_size >= layout.size() {
          let now = CURRENT.fetch_add(new_size - layout.size(), Ordering::Relaxed) +
            (new_size - layout.size());
          PEAK.fetch_max(now, Ordering::Relaxed);
        } else {
          CURRENT.fetch_sub(layout.size() - new_size, Ordering::Relaxed);
        }
      }
      new
    }
  }

  #[global_allocator]
  static GLOBAL: Counting = Counting;

  pub(super) fn measure<T>(f: impl FnOnce() -> T) -> (T, usize) {
    let base = CURRENT.load(Ordering::Relaxed);
    PEAK.store(base, Ordering::Relaxed);
    let res = f();
    (res, PEAK.load(Ordering::Relaxed) - base)
  }
}

#[test]
#[ignore]
fn e007_measure_verify() {
  const ITERS: usize = 15;
  let (G, T, U, V, params) = random_params(8);
  for (paths, layers) in [(1, 7), (1, 8), (2, 8), (4, 8), (8, 8)] {
    let (proof, root, inputs) = random_proof(&params, (G, T, U, V), paths, layers);
    let mut times = [vec![], vec![]];
    let mut peaks = [vec![], vec![]];
    for _ in 0 .. ITERS {
      for (i, streaming) in [true, false].into_iter().enumerate() {
        let mut verifier_1 = generalized_bulletproofs::Generators::batch_verifier();
        let mut verifier_2 = generalized_bulletproofs::Generators::batch_verifier();
        let start = std::time::Instant::now();
        let (res, peak) = e007_measure::measure(|| {
          if streaming {
            proof.verify(&mut OsRng, &mut verifier_1, &mut verifier_2, &params, root, layers, &inputs)
          } else {
            proof.verify_stored(
              &mut OsRng,
              &mut verifier_1,
              &mut verifier_2,
              &params,
              root,
              layers,
              &inputs,
            )
          }
        });
        times[i].push(start.elapsed().as_micros());
        peaks[i].push(peak);
        res.unwrap();
        assert!(batch_verifies(&params, &verifier_1, &verifier_2));
      }
    }
    for v in &mut times {
      v.sort_unstable();
    }
    for v in &mut peaks {
      v.sort_unstable();
    }
    let med = |v: &Vec<u128>| v[v.len() / 2];
    println!(
      "E007 inputs={paths} layers={layers} | streaming: median {}us (min {} max {}), peak heap {} B (min {} max {}) | stored: median {}us (min {} max {}), peak heap {} B (min {} max {})",
      med(&times[0]), times[0][0], times[0][ITERS - 1],
      peaks[0][ITERS / 2], peaks[0][0], peaks[0][ITERS - 1],
      med(&times[1]), times[1][0], times[1][ITERS - 1],
      peaks[1][ITERS / 2], peaks[1][0], peaks[1][ITERS - 1],
    );
  }
}
