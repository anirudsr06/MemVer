# From Top to Bottom :

c-class/src/ccore.bsv:
1. Addition of AXI4 interface for tree_mem module. 
2. Tree memory address read request sent by dmem -> axi 
3. Tree memory data read response sent by axi -> dmem 
4. Tree memory data write from dmem -> axi 
5. Axi responds with ack after write 

c-class/src/stage5.bsv:
1. Not sure if the ifdef dcache endif is necessary in line 438

Soc.bsv:
1. Connect tree master axi line to ccore
2. Increase Num_Fast_Masters to 4, and label Tree_master_num as 3 

caches_mmu/src/dcache/dmem.bsv:
1. Interface mvu and tree memory
2. Connect dcache and mvu for pre-load verification
3. Connect MVU and tree memory for node fetching
4. Method to write back to treemem for node update

caches_mmu/src/dcache/mvu.bsv:


caches_mmu/src/dcache/hcache.bsv: 

