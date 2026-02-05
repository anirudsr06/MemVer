/*
HCache.bsv
Stores the Merkle Tree nodes (Level 1 hashes) for verification.
*/
package hcache;

import RegFile :: *;
import Vector :: *;
import DReg :: *;

`include "dcache.defines"

// Configuration constants
typedef 64 HashWidth; // 8-byte (64 bit) Hash for XOR folding
typedef 15 IndexWidth; // 2MB / 64B = 32,768 entries -> 15 bits

// Subject to change
Bit#(`paddr) protected_base = 'h0000_0000; // Starting at 0 for your test case
Bit#(`paddr) protected_limit = 'h0020_0000; // 2 MB size

interface Ifc_HCache;
    method ActionValue#(Maybe#(Bit#(HashWidth))) get_expected_hash(Bit#(`paddr) addr);    
    method Action update_hash(Bit#(`paddr) addr, Bit#(HashWidth) hash);
    method Bool is_protected(Bit#(`paddr) addr);
endinterface

(* synthesize *)
module mkHCache(Ifc_HCache);

    // 1 Valid bit + Hash
    RegFile#(Bit#(IndexWidth), Bit#(TAdd#(HashWidth,1))) rf_hashes <- mkRegFileFull;

    // Obtain block
    function Bit#(IndexWidth) get_index(Bit#(`paddr) addr);
        Bit#(`paddr) offset = addr - protected_base;
        return truncate(offset >> 6); // 64-byte address
    endfunction

    // Verify whether memory comes from protected region
    function Bool is_protected(Bit#(`paddr) addr);
        return (addr >= protected_base && addr < protected_limit);
    endfunction


    method ActionValue#(Maybe#(Bit#(HashWidth))) get_expected_hash(Bit#(`paddr) addr);
        if (is_protected(addr)) begin
            let idx = get_index(addr);
            Bit#(TAdd#(HashWidth,1)) entry = rf_hashes.sub(idx);
            if (entry[valueOf(HashWidth)] == 1'b1)
                return tagged Valid entry[valueOf(HashWidth) - 1:0];
            else 
                return tagged Invalid;
        end
        else begin
            return tagged Invalid;
        end
    endmethod

    method Action update_hash(Bit#(`paddr) addr, Bit#(HashWidth) hash);
        if (is_protected(addr)) begin
            let idx = get_index(addr);
            rf_hashes.upd(idx, {1'b1,hash});
            $display("[HCache] Updated Hash for Addr: %h (Idx: %d) -> %h", addr, idx, hash);
        end
    endmethod

endmodule

endpackage