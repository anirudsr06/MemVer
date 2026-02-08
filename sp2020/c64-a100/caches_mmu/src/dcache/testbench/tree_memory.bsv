/*
Tree Memory Module for MVU Testbench
Provides a mock tree memory that stores sibling nodes for Merkle tree verification testing.

Uses a Vector of Regs instead of RegFile to allow parallel reads.
*/

package tree_memory;

import FIFOF::*;
import GetPut::*;
import Vector::*;
import mvu::*;

// Total storage: 16 levels * 256 entries = 4096 entries
typedef 4096 NumEntries;
typedef TLog#(NumEntries) AddrWidth;

// Entry: {valid, hash}
typedef Bit#(TAdd#(HashWidth, 1)) Entry;

interface Ifc_TreeMemory;
    // Request/response for tree node fetches
    interface Put#(TreeNodeReq) put_req;
    interface Get#(TreeNodeResp) get_resp;
    
    // Preload nodes for testing (level, index, hash)
    method Action preload(Level level, TreeIndex index, Bit#(HashWidth) hash);
endinterface

(* synthesize *)
module mkTreeMemory(Ifc_TreeMemory);
    
    // Use a vector of registers for storage (allows parallel reads)
    Vector#(NumEntries, Reg#(Entry)) v_nodes <- replicateM(mkReg(0));
    
    FIFOF#(TreeNodeReq) ff_req <- mkFIFOF;
    FIFOF#(TreeNodeResp) ff_resp <- mkFIFOF;
    
    // Pack level and index into storage address
    function Bit#(AddrWidth) pack_addr(Level level, TreeIndex index);
        // Use lower bits of level and index
        Bit#(4) lvl = level;
        Bit#(8) idx = truncate(index);
        return truncate({lvl, idx});
    endfunction
    
    // Process requests - read all 8 siblings
    rule rl_process_req;
        let req = ff_req.first;
        ff_req.deq;
        
        Vector#(Arity, Bit#(HashWidth)) hashes = replicate(0);
        Vector#(Arity, Bool) valid = replicate(False);
        
        // Read all 8 siblings
        for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
            TreeIndex idx = req.base_index + fromInteger(i);
            Bit#(AddrWidth) addr = pack_addr(req.level, idx);
            Entry entry = v_nodes[addr];
            
            if (entry[valueOf(HashWidth)] == 1'b1) begin
                hashes[i] = truncate(entry);
                valid[i] = True;
                $display("[TreeMem] Read L%0d[%0d] = %h", req.level, idx, hashes[i]);
            end else begin
                $display("[TreeMem] Read L%0d[%0d] = EMPTY", req.level, idx);
            end
        end
        
        ff_resp.enq(TreeNodeResp {
            hashes: hashes,
            valid: valid
        });
    endrule
    
    interface put_req = toPut(ff_req);
    interface get_resp = toGet(ff_resp);
    
    method Action preload(Level level, TreeIndex index, Bit#(HashWidth) hash);
        Bit#(AddrWidth) addr = pack_addr(level, index);
        v_nodes[addr] <= {1'b1, hash};
        $display("[TreeMem] Preload L%0d[%0d] = %h", level, index, hash);
    endmethod
    
endmodule

endpackage
