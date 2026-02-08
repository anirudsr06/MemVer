/*
HCache.bsv - Refactored for Sparse Merkle Tree
Stores only the TOP levels of the tree (near root) in hardware.
Lower levels are computed on-demand and verified against stored upper levels.

Tree Structure (Arity 8):
- Each leaf = 8 bytes (one beat)
- Each parent = hash of 8 children
- Cache line = 64 bytes = 8 consecutive leaves

Example for 2MB protected region:
  Level 0: 2MB / 8B = 262,144 leaves
  Level 1: 262,144 / 8 = 32,768 nodes
  Level 2: 32,768 / 8 = 4,096 nodes
  Level 3: 4,096 / 8 = 512 nodes
  Level 4: 512 / 8 = 64 nodes
  Level 5: 64 / 8 = 8 nodes
  Level 6: 8 / 8 = 1 node (root)

We store levels 3-6 in HCache (4 levels, ~4.5KB)
*/

package hcache;

import RegFile :: *;
import Vector :: *;

`include "dcache.defines"

// Configuration constants
typedef 64 HashWidth;          // Hash size in bits
typedef 18 MaxLeafIndexWidth;  // 2MB / 8B = 256K leaves = 18 bits
typedef 6  TreeHeight;         // Height of tree (0-6 for 2MB)
typedef 4  TopLevelsStored;    // Store top 4 levels in HW (levels 3-6)

// Compute max nodes at highest stored level
// Level 3 has 512 nodes, so we need 9 bits for index
typedef 9 MaxStoredIndexWidth;

// Address width for HCache: level_offset (2 bits for 4 levels) + index
typedef TAdd#(2, MaxStoredIndexWidth) HAddrWidth;

// Level type
typedef Bit#(4) Level;  // 0-15 (though we only use 0-6)

// Index type (sized for largest level we might handle)
typedef Bit#(MaxLeafIndexWidth) TreeIndex;

interface Ifc_HCache;
    // Get hash for a node at (level, index)
    method ActionValue#(Maybe#(Bit#(HashWidth))) get_hash(Level level, TreeIndex index);

    // Set hash for a node
    method Action set_hash(Level level, TreeIndex index, Bit#(HashWidth) hash);

    // Check if this level is stored in HW
    method Bool is_hw_level(Level level);
    
    // Get the minimum HW level (below this, nodes are in memory)
    method Level min_hw_level();
    
    // Compute level from leaf index
    method Level get_tree_height();
    
    // Protected region management
    method Bool is_protected(Bit#(`paddr) addr);
    method TreeIndex addr_to_leaf_index(Bit#(`paddr) addr);
endinterface

(* synthesize *)
module mkHCache(Ifc_HCache);

    // Storage: {valid, hash}
    RegFile#(Bit#(HAddrWidth), Bit#(TAdd#(HashWidth,1))) rf_nodes <- mkRegFileFull;

    // Protected region configuration
    Bit#(`paddr) protected_base = 'h0000_0000;
    Bit#(`paddr) protected_limit = 'h0020_0000; // 2 MB

    // Tree configuration
    Integer tree_height = valueOf(TreeHeight);
    Integer top_levels = valueOf(TopLevelsStored);
    Integer min_hw_lvl = tree_height - top_levels; // 6 - 4 = 2 (but we want 3, so add 1)
    // Actually: if we store 4 levels (3,4,5,6), min is 3
    Integer actual_min_hw_level = tree_height - top_levels + 1; // 6 - 4 + 1 = 3

    // Check if level is stored in HW
    function Bool is_hw_level_func(Level level);
        return (level >= fromInteger(actual_min_hw_level) && 
                level <= fromInteger(tree_height));
    endfunction

    // Map tree level to internal storage offset
    // Level 6 (root) -> offset 0
    // Level 5 -> offset 1
    // Level 4 -> offset 2
    // Level 3 -> offset 3
    function Bit#(2) level_to_offset(Level level);
        return truncate(fromInteger(tree_height) - level);
    endfunction

    // Pack level offset + index into storage address
    function Bit#(HAddrWidth) pack_addr(Level level, TreeIndex index);
        let offset = level_to_offset(level);
        let idx = truncate(index); // Truncate to max stored index width
        return {offset, idx};
    endfunction

    // Convert address to leaf index
    function TreeIndex addr_to_leaf_index_func(Bit#(`paddr) addr);
        Bit#(`paddr) offset = addr - protected_base;
        return truncate(offset >> 3); // Divide by 8 (leaf size)
    endfunction

    // Protected region check
    function Bool is_protected_func(Bit#(`paddr) addr);
        return (addr >= protected_base && addr < protected_limit);
    endfunction

    method ActionValue#(Maybe#(Bit#(HashWidth))) get_hash(Level level, TreeIndex index);
        if (!is_hw_level_func(level)) begin
            // Not in HW cache
            return tagged Invalid;
        end else begin
            let addr = pack_addr(level, index);
            let entry = rf_nodes.sub(addr);

            if (entry[valueOf(HashWidth)] == 1'b1)
                return tagged Valid entry[valueOf(HashWidth)-1:0];
            else
                return tagged Invalid;
        end
    endmethod

    method Action set_hash(Level level, TreeIndex index, Bit#(HashWidth) hash);
        if (is_hw_level_func(level)) begin
            let addr = pack_addr(level, index);
            rf_nodes.upd(addr, {1'b1, hash});
            $display("[HCache] Set: L%0d[%0d] = %h", level, index, hash);
        end else begin
            $display("[HCache] WARNING: Attempted to store non-HW level %0d", level);
        end
    endmethod

    method Bool is_hw_level(Level level);
        return is_hw_level_func(level);
    endmethod
    
    method Level min_hw_level();
        return fromInteger(actual_min_hw_level);
    endmethod
    
    method Level get_tree_height();
        return fromInteger(tree_height);
    endmethod
    
    method Bool is_protected(Bit#(`paddr) addr);
        return is_protected_func(addr);
    endmethod
    
    method TreeIndex addr_to_leaf_index(Bit#(`paddr) addr);
        return addr_to_leaf_index_func(addr);
    endmethod

endmodule

endpackage
