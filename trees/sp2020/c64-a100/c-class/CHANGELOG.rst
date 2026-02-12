
CHANGELOG
=========

This project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[1.9.6] - 2020-06-05
--------------------

- put pmp related logic under `ifdef pmp` in ccore.bsv
- make the Addr_space configurable through YAML
- update schema_file comments for better readibility
- reset value of mstatus.mie is 0 even if openocd is enabled.
- minimal comments updated in stage0

[1.9.5] - 2020-05-13
--------------------

- removed the concept of extra history bits from gshare_fa
- added historybits as a new parameter to indicate the size of bits used from the ghr for indexing.
- reduced tick resolution in test_soc
- updated the 2 bit counter increment scheme to account for hysterisis bit separately
- updated the gshare has function for improved collisions
- updated repomanager to 1.2.0

[1.9.4] - 2020-04-30
--------------------

- parallel build using bluetcl is enabled
- remove re-alignment of bytes in ccore for I$ and D$ reads. This now is handled within the caches
- bumped version of the caches
- gitignore updated
- fixed and cleaned up the interrupt and delegation logic
- adding pre-requisite checks in configure
- default.yaml is picked up as default if no argument given to -ispec
- split interface of seip and meip. Both can now be driven by plic independently. Also led to removal of unwated attributes.


[1.9.3] - 2020-04-30
--------------------

- fixed reset logic handling in ccore.bsv to support reset by debugger.
- updated SoC to decouple debug related logic into a separate module. This now allows for easy reset
  control.
- the debug module in the test-soc is now always enabled irrespective of the debug being enabled or
  not
- Fixed minor bug in Makefile when compiling for GDB sim.
- moved debug loop and dtvec_base to 0x100

[1.9.2] - 2020-04-26
--------------------

Fixed
^^^^^
- [docs] move pip install requirements to building core section
- [docs] fixed typos in simulation section and added dhrystone benchmarking method
- updating verification repo version to avoid dirname error

Changed
^^^^^^^
- renamed cclass to ccore at all instances


[1.9.1] - 2020-04-07
--------------------

Fixed
^^^^^
- when pmps are not implemented then return 0 instead
- bug fixed in csr trap handler logic when only usertraps enabled without supervisor
- enable openocd macros in configure and clean up performance counter macro generation
- link verilator target for gdb compile fixed
- exit ci for patch updates
- adding missing supervisor and user macros in decoder to enable correct debug functionality
- 32-bit default config updated to new schema

Changed
^^^^^^^
- updated method and rule attributes related to csrs for cleaner compile
- using SizedFIFO instead of LFIFO to avoid unwanted scheduling

Removed
^^^^^^^
- removing old msb lsb files and replacing with a single file
- adding sections in ci file


[1.9.0] - 2020-04-03
--------------------


Added
^^^^^
* pmp support fixed
* pmp support enabled in config
* adding iitm copyright in configure log
* adding pmp support documentation
* adding pipeline image in introduction

Changed
^^^^^^^
* changed schema of warnings to be a list
* defaulting to suppress all warnings
* removing old storebuffer module
* moving micro arch related chapters under a single micro-arch-notes chapter

Fixed
^^^^^
* adding dummy arprot field to remove warning
* rg_stall available only under multicycle macro
* corrected conditions under which pmpcfg and pmpaddr can be written
* fixed logic for pmp access permissions in decoder


[1.8.0] - 2020-04-01
--------------------

Added
^^^^^
* integration with optimized 1rw dcache and icache
* support for ecc on both caches
* suppot for dual ported-rams in dcache


[1.7.3] - 2020-03-24
--------------------

Added
^^^^^
* note to install and follow steps available on the original repositories for all external tools

[1.7.2] - 2020-03-23
--------------------

Fixed
^^^^^
* fixed steps for bsc install in quickstart


[1.7.1] - 2020-03-10
--------------------

Fixed
^^^^^
* Doc updates
* Use v7.0.1 of the caches with new bram interfaces
* Store being dropped in the commit stage should wait for the cache to be ready.

[1.7.0] - 2020-03-02
--------------------

Changed
^^^^^^^

* config file is now yaml based
* docs moved to read-the-docs
* restructured directories. base-sim is no longer present. All tests have been moved to
  micro-arch-tests.
* LICENSE files have been upgraded
* common_types.bsv renamed to cclass_types.bsv
* common_params.bsv renamed to cclass_params.defines
* removed unwanted ifdef simulate macros
* Makefile has been update to use the new configuration setup and use the open-bsc tool from
  henceforth.
* moved CHANGELOG to rst syntax
* modifications to use the new 1rw dcache with better freq closure.
* more comment updates in some modules

Added
^^^^^

* Added a new python based configuration setup

[1.6.1] - 2019-11-21
--------------------

Fixed
^^^^^

* The indication of whether a instruction-page-fault was due to the lower-16 bits or the upper-16
  bits has been fixed.

[1.6.0] - 2019-11-21
--------------------

Fixed
^^^^^

* upstream verification with virtual mode runs
* updated ci

[1.5.0] - 2019-11-21
--------------------

Added
^^^^^

* added support for ITIM and DTIM
* new csrs to define the address map of the ITIM and DTIM
* directed tests for performance counters and Tightly-integrated memories
* doc update for custom csrs of c-class done.

Fixed
^^^^^

* interrupt mask when debbuger is enabled has been fixed.

[1.4.2] - 2019-11-08
--------------------

Added
^^^^^

* macro for reset value of dtvec csr
* updated doc and template with the macro

[1.4.1] - 2019-10-29
--------------------

Fixed
^^^^^

* Makefile to detect tools directory for artifacts release.

[1.4.0] - 2019-10-28
--------------------

Added
^^^^^

* support for WFI
* support for illegal trapping when tvm, tw and tsr registers are set in supervisor mode
* verilog artifacts now have rtldump support and logger support.
* 256MBytes of BRAM for verilog artifact simulation

Fixed
^^^^^

* made ADDR_SPACE as a variable in config file
* fixed paramaters for linux template
* bumped verification version to 3.2.4
* access to csr 0x321 and 0x322 now generates trap
* bumping devices to 5.0.0 with new uart features.
* fixed verilator setup for gdb as well
* added suppresswarnings as part of the gitlab ci/cd

[1.3.6] - 2019-10-22
--------------------

Added
^^^^^

* Micro Arch ppt of the core pipeline.

[1.3.5] - 2019-10-16
--------------------

Fixed
^^^^^

* verification update for csmith path fix. Close #152

[1.3.4] - 2019-10-16
--------------------

Fixed
^^^^^

* Illegal instruction generation script. Close #151

[1.3.3] - 2019-10-08
--------------------

Fixed
^^^^^

* Illegal encoding were being treated as FCVT.D.S and FCVT.S.D. This has been fixed. Close #149

[1.3.2] - 2019-10-04
--------------------

Fixed
^^^^^

* Passing arith_en to FPU which enables arith_traps Close #147

[1.3.1] - 2019-10-04
--------------------

Fixed
^^^^^

* Traps for floating point ops with ARITH_TRAP enabled but disabled through csr no longer generates
  traps. Close #147

[1.3.0] - 2019-10-03
--------------------

Added
^^^^^

* bumped to caches with ECC support. Added corresponding hooks and details in readme as well.

Fixed
^^^^^

* typos in readme fixed #138
* improved verilator build speed.

[1.2.5] - 2019-10-01
--------------------

Fixed
^^^^^

* compile issues with arith_trap enabled fixed
* decoding for WFI fixed.

[1.2.4] - 2019-09-28
--------------------

Added
^^^^^

* scripts and edits to collect coverage from verilator sim

[1.2.3] - 2019-09-27
--------------------

Fixed
^^^^^

* mie and mip widths fixed when compiling with debug mode enabled. refer to issue #144.

[1.2.2] - 2019-09-26
--------------------

Changed
^^^^^^^

* tracking cache misses instead of hits. refer to issue #143 for more info.
* updated performance tests with encodings.

[1.2.1] - 2019-09-26
--------------------

Fixed
^^^^^

* fixed mm benchmark to print stats at end of program

[1.2.0] - 2019-09-26
--------------------

Fixed
^^^^^

* performance counter increment conditions and interrupt generation scheme. A counter will not
  increment if the respective interrupt has been set.
* the last daisy-module instantiated should respond with true and data=0
* fixed op-fwding bug mentioned in issue #140
* decoding performance counters is fixed now. refer issue #141

Added
^^^^^

* added tests and benchmarks for performance counters.

Removed
^^^^^^^

* removed redundant epoch register and method from stage4

[1.1.1] - 2019-09-16
--------------------

Fixed
^^^^^

* ci-cd script fixed to delete all generated files

[1.1.0] - 2019-09-16
--------------------

Added
^^^^^

* CSRs are now daisy chained.
* Performance counters and their event encodings added.
* Interrupts for counters has also been added.
* Increased default bram size in TB to be 32MB. This has increased regression time but now the same
  executable can be used for linux sim as well

Fixed
^^^^^

* BRAM now uses only a single file: ``code.mem`` for read-only. MSB and LSB files no longer required.
* Updated docs to reflect new additions and fixes made above.
* renamed a few methods based on the coding guidelines.

[1.0.3] - 2019-09-10
--------------------

Added
^^^^^

* makefile now uses bsvpath to identify directories for bsv source. This makes using vim-bsv easier.

[1.0.2] - 2019-09-10
--------------------

Fixed
^^^^^

* rg_delayed_redirect register in stage0 should only be used when bpu and compressed both enabled.

[1.0.1] - 2019-09-09
--------------------

Fixed
^^^^^

* links to verilog artifacts in readme fixed.

[1.0.0] - 2019-09-09
--------------------

Fixed
^^^^^

* data types of ISBs has been split to keep logic minimal and optimize frequency closure
* Logger is used in all submodules.
* macros and configurable options have been fixed to be more precise and granular
* stage0 or pc-fetch stage with fully-associative gshare has been fixed and tuned for higher
  frequency closure
* ALU has ben further optimized for better freqency closure
* ISB types and operand forwarding tuned for better frequency closure.
* overall changes to remove trailing white-spaces from all files.
* version extraction based on CHANGELOG will be followed hence forth.
* fpu convert from dp to sp roundup conditions fixed.

Added
^^^^^

* decompressor function added in stage1
* reset-pc can now be controlled by the SoC as an input without having to compromize on synthesi
  boundaries
* retimed multiplier with configurable stages is used always.
* different multiplier modules for evaluation have also been added.
* fully-associative TLB support has also been added.
* configuration support to supress all warnings during bsv compile
* CHANGELOG will be maintained from these release onwards.

Removed
^^^^^^^

* bimodal bpu support has been removed for now since it needs to be re-structured based on new
  interfaces and also requires new verilog-bram models
* gshare index model has also been removed along the same arguments as above.
* support for variable cycle mutliplier has also been removed as part of this release.
