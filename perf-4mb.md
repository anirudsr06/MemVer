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
  | Sequential (Seq)     | 2524 | 315 |
  | Random/Striped (Rnd) | 2600 | 325 |
  +----------------------+--------------------+--------------------+

  Spatial Locality benefit: Sibling D-Cache hit provides a +3% speedup!

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
  | 2 | 807 | 403 |
  | 4 | 1362 | 340 |
  | 8 | 2490 | 311 |
  | 16 | 4736 | 296 |
  | 24 | 6978 | 290 |
  | 32 | 9224 | 288 |
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
  | Vector Copy     | 1034282 | 4511373 | 336% |
  | Vector Add      | 2175924 | 14001081 | 543% |
  | Binary Search   | 135343 | 256764 | 89% |
  +-----------------+------------------+------------------+------------+

  Notes:
  - Binary Search accesses memory sparsely, highlighting the on-demand
    verification latency.
  - Vector Copy/Add test stream throughput with MVU overhead.

===========================================================
