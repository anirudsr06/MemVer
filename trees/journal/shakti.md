# Shakti processor architecture

For the most part the architecture is similar to the intel pentium (using it as reference since we already know pentium's architecture)

1. Using RISC-V instead of CISC as we saw in x86 processors like pentium. 
2. Instead of a dual pipeline as the pentium, the shakti core only implements a 5 stage single pipeline.
Fetch -> Decode -> Execute -> Memory -> Write Back 

The stages are simple and mean what the name says. 
Fetch – Get the instruction from memory.
Decode – Figure out what the instruction means.
Execute – Do the calculation or prepare for memory access.
Memory – Load or store data if needed.
Write Back – Save the result into the register file.

## Register file and CSR: 
RISC-V processors have 32 important registers, and a bunch of special control and status registers that contain system information. 

If we look at each stage:

1. Instruction Fetch and Branching:

Fetch instructions from instruction cache, or load instructions from memory onto instruction cache. Store predicted branch address in BTB. Generate address of next instruction (predict where necessary), and handle mispredictions. 

2. Decode and Operand Fetch: 

Fetch operand from register and csr file. Decode instructions fetched from previous stage. 

3. Execution 

Use built ALU unit. Special feature - processes can jump from this stage directly to writeback if necessary. Processes can also directly jump to this stage if a particular result is required for next instruction before writeback.

4. Memory Access 

Interacts with dcache for load and store instructions. Handles address translation, and ptwalk when missed. 

5. Writeback 

As simple as it sounds, writes back into register file.

We should probably focus on the Memory access, and instruction fetch stages, since those are the ones that will be accessing data from memory. Implement SMT on memory and find a way to integrate it with these stages to validate integrity of data. 

## Decoding the Stages on the SoC's bluespec implementation 

Stage0: (./src/)
