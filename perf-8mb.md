===========================================================
  MVU PERF BENCHMARK 1: Read vs. Write Latency
  Rounds: 100
===========================================================

  PERFORMANCE COMPARISON TABLE (Average Cycles)
  +---------------------+-------------+-----------+-----------------+
  | Operation           | Unprotected | Protected | MVU Cost/Diff   |
  +---------------------+-------------+-----------+-----------------+
  | Cache Hit Read      | 271 | 483 | 212 |
  | Cache Hit Write     | 280 | 780 | 500 |
  | Cache Miss Read     | 286 | 483 | 197 |
  | Cache Miss Write    | 335 | 276 | -59 |
  +---------------------+-------------+-----------+-----------------+

  Observations:
  - Cache Hit paths should have nearly identical latency (~0 overhead).
  - Cache Miss Read cost includes fetching siblings and tree hashing.
  - Cache Miss Write cost shows the eviction latency penalty.

===========================================================

===========================================================
  MVU PERF BENCHMARK 2: Sibling Fetch Cache Locality
  Lines: 8
===========================================================

  Running Sequential Walk (high locality)...
  Running Random/Striped Walk (low locality)...

  LOCALITY PERFORMANCE BENCHMARK RESULT
  +----------------------+--------------------+--------------------+
  | Walk Pattern         | Total Cycle Cost   | Avg Cycles / Line  |
  +----------------------+--------------------+--------------------+
  | Sequential (Seq)     | 2538 | 317 |
  | Random/Striped (Rnd) | 2608 | 326 |
  +----------------------+--------------------+--------------------+

  Spatial Locality benefit: Sibling D-Cache hit provides a +2% speedup!

===========================================================

===========================================================
  MVU PERF BENCHMARK 3: Working Set Scaling & D-Cache Thrashing
  Rounds: 30
===========================================================

  Starting benchmark scaling rounds...

  +--------------+------------------+-----------------+
  | Working Set  | Total Read Cycle | Avg Cycles/Line |
  | (Cache Lines)| (Verify Round)   | (Verify latency)|
  +--------------+------------------+-----------------+
  | 1 | 529 | 529 |
  | 2 | 805 | 402 |
  | 4 | 1357 | 339 |
  | 8 | 2490 | 311 |
  | 16 | 4736 | 296 |
  | 24 | 6979 | 290 |
  | 32 | 9223 | 288 |
  +--------------+------------------+-----------------+

  Observations:
  - As Working Set increases, conflict misses in Dcache cause sibling
    fetches to drop out, leading to scaling degradation.

===========================================================

===========================================================
  MVU PERF BENCHMARK 4: Real-world Mixed Workloads
  Array Size: 64 elements | Iterations: 200
===========================================================

  MIXED WORKLOAD BENCHMARK COMPARISON
  +-----------------+------------------+------------------+------------+
  | Kernel          | Unprotected (cyc)| Protected (cyc)  | Overhead % |
  +-----------------+------------------+------------------+------------+
  | Vector Copy     | 1034279 | 4511454 | 336% |
  | Vector Add      | 2175990 | 14001074 | 543% |
  | Binary Search   | 129687 | 256920 | 98% |
  +-----------------+------------------+------------------+------------+

  Notes:
  - Binary Search accesses memory sparsely, highlighting the on-demand
    verification latency.
  - Vector Copy/Add test stream throughput with MVU overhead.

===========================================================
