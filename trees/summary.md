# Project MemVer

## What is the problem we are trying to solve?

1. Untrusted Memory - What does it mean?
Trusted memory is data that we know hasn't been tampered with. Locations of data that are susceptible to being modified, and allowed access to attackers. This is clearly a problem. It may lead to incorrect results, or leak of private information. The possibilites are endless.
2. Overseeing instruction delocalization
How do I know the result you obtained by running my instructions on your computer is legitimate?
3. Protection from physical tampering

## How do we approach the solution?

Hashing is irreversible and collision resistant. So what if we employed a hash-verification scheme like blockchains do. A hash tree is a data structure that has a tree-like structures. Leaves are the most basic data elements, that are hashed in couples to form branches, recursively until a root is obtained. This is essentially what a Merkle tree is. A Sparse Merkel tree is similar, but it is set to pre-defined size, with default values, and as values get updated, the tree is reconstructed with optimized minimal updations. 

### But what about speed? I have to perform so many expensive hash computations, construct a massive data tree each time I try to verify my data

Caches are fast memory access locations in or near the CPU that can be considered secured in terms of physical tampering is concerned. Although data from here can be extracted by side-channel means. So we can store our merkel proofs in cache memory. We know whatever is stored in here cannot be tampered with. Compared the calculated root from received data, and verify with the on-chain merkel tree. When new data is read by the processor, it can create a new root for the particular sub-tree, verify with it's parent root, and add it onto the cache. 

### What are the other issues with implementing merkle trees?

1. Node values for the merkle trees take up a lot of space on the cache, and hence reducing available space for actual data, hence compromising processing speeds.
2. Trees only cover data from RAM, so disk data cannot be protected. If an attacker modifies data on a disk, later when it's loaded onto the RAM, the parent hash will be updated as required.

## Key considerations

1. Direct Memory Access
Other hardware components read from and write to memory. This makes it really hard to keep the tree updated, and verify all this data's integrity. Solutions to this may include smart implementations of isolating sections of memory for these "dirty data" values, and have them copied into the trusted sections and simultaneously updating the tree. 

2. Initialization 
While starting up secure mode, hash trees for the entire memory has to be generated correctly. To optimize that, we can turn on hashing for writes, and write to every memory chunk that needs to be protect -- this adds it onto the cache. Then flushing this "dirty" data, writing it back to memory so that it's parent hashes are updated. 

3. Signing
Operations that require result signing from the processor's secret key must wait to be validated completely before signing, in case of failure, no signed result should be computed.
