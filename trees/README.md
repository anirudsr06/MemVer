Trees

This folder contains the implementation and analysis of Merkle hash trees, including a focus on sparse Merkle trees.

algo_flow.png: A flowchart of the update algorithm for a Merkle tree, detailing the steps from input to updating the root hash.

mkt-sha256.cpp: An implementation of a standard binary Merkle tree. The code includes functions to build the tree, update nodes, and verify data with the root hash.

smkt-sha256.cpp: An implementation of a Sparse Merkle Tree (SMT) using SHA-256.

graph.py: A Python script that generates heatmaps to visualize Merkle tree performance.

Arity & Chunk Size.doc: A document that explains the key parameters that affect Merkle tree performance. It provides formulas for calculating height, proof size, and memory overhead, and compares different arities to determine the most efficient configuration.
