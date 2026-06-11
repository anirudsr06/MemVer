===========================================================
  MVU PERF BENCHMARK 1: Read vs. Write Latency
  Rounds: 100
===========================================================

  PERFORMANCE COMPARISON TABLE (Average Cycles)
  +---------------------+-------------+-----------+-----------------+
  | Operation           | Unprotected | Protected | MVU Cost/Diff   |
  +---------------------+-------------+-----------+-----------------+
  | Cache Hit Read      | 272 | 428 | 156 |
  | Cache Hit Write     | 279 | 636 | 357 |
  | Cache Miss Read     | 286 | 428 | 142 |
  | Cache Miss Write    | 335 | 277 | -58 |
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
  | Sequential (Seq)     | 2083 | 260 |
  | Random/Striped (Rnd) | 2147 | 268 |
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
  | 1 | 474 | 474 |
  | 2 | 699 | 349 |
  | 4 | 1145 | 286 |
  | 8 | 2041 | 255 |
  | 16 | 3835 | 239 |
  | 24 | 5602 | 233 |
  | 32 | 7405 | 231 |
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
  | Vector Copy     | 1034287 | 3581928 | 246% |
  | Vector Add      | 2175891 | 10807224 | 396% |
  | Binary Search   | 135353 | 223882 | 65% |
  +-----------------+------------------+------------------+------------+

  Notes:
  - Binary Search accesses memory sparsely, highlighting the on-demand
    verification latency.
  - Vector Copy/Add test stream throughput with MVU overhead.

===========================================================
