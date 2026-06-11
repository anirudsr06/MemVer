PROTECTED REGION = 2MB
LEVELS = 6

==== MVU BENCH ====

[A] Unprot RW: 24145
[B] Prot RW:   23302
[C] Prot Read: 436
[D] Unprot Read:284
MVU Cost (C-D): 152 cycles

[STREAM]
  Unprot: 32737925
  Prot:   37985958

[RANDOM]
  Unprot: 36471057
  Prot:   41752941

[WRITE]
  Unprot: 40050518
  Prot:   50485746

DONE

================================================
  MVU PERFORMANCE BENCHMARK
  R/W tests: 1000 iters, Evict tests: 200 iters
================================================

[WARMUP] Seeding hash tree for protected addresses...
[WARMUP] Done. No traps (hash tree seeded correctly).

[BENCH A] Unprotected read/write (baseline)...
  Cycles: 1140677  (1140 per iter)
[BENCH B] Protected read/write (cache-hot)...
  Cycles: 3909120  (3909 per iter)
[BENCH C] Protected evict+read (MVU verify each)...
  Cycles: 79232  (396 per iter, 0 traps)
[BENCH D] Unprotected evict+read (eviction baseline)...
  Cycles: 47585  (237 per iter)

================================================
  SUMMARY (cycles per iteration)
================================================
  A) Unprotected R/W (baseline):  1140
  B) Protected R/W (cache-hot):   3909
  C) Protected evict+read (MVU):  396
  D) Unprotected evict+read:      237
  MVU verify cost (C-D):          159 cycles
  MVU overhead %:                  66%
  Traps during benchmarks:        0


PROTECTED REGION = 8MB
LEVELS = 7


================================================
  MVU PERFORMANCE BENCHMARK
  R/W tests: 1000 iters, Evict tests: 200 iters
================================================

[WARMUP] Seeding hash tree for protected addresses...
[WARMUP] Done. No traps (hash tree seeded correctly).

[BENCH A] Unprotected read/write (baseline)...
  Cycles: 1139826  (1139 per iter)
[BENCH B] Protected read/write (cache-hot)...
  Cycles: 5007590  (5007 per iter)
[BENCH C] Protected evict+read (MVU verify each)...
  Cycles: 89455  (447 per iter, 0 traps)
[BENCH D] Unprotected evict+read (eviction baseline)...
  Cycles: 47368  (236 per iter)

================================================
  SUMMARY (cycles per iteration)
================================================
  A) Unprotected R/W (baseline):  1139
  B) Protected R/W (cache-hot):   5007
  C) Protected evict+read (MVU):  447
  D) Unprotected evict+read:      236
  MVU verify cost (C-D):          211 cycles
  MVU overhead %:                  88%
  Traps during benchmarks:        0
================================================

==== MVU BENCH ====

[A] Unprot RW: 24141
[B] Prot RW:   23354
[C] Prot Read: 489
[D] Unprot Read:283
MVU Cost (C-D): 206 cycles

[STREAM]
  Unprot: 32670954
  Prot:   39652663

[RANDOM]
  Unprot: 36458009
  Prot:   43419905

[WRITE]
  Unprot: 39741434
  Prot:   54861862

DONE


