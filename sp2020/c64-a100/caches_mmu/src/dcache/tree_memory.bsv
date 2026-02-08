/*
Tree Memory Simulator
Simulates memory storage of tree nodes below the HCache levels.
In a real system, this would be integrated with the memory controller.
*/

package tree_memory;

import FIFOF::*;
import FIFO::*;
import GetPut::*;
import Vector::*;
import RegFile::*;
import mvu::*;

typedef 64 HashWidth;
typedef 8 Arity;
typedef Bit#(4) Level;
typedef Bit#(18) TreeIndex;

interface Ifc_TreeMemory;
    interface Put#(TreeNodeReq) put_req;
    interface Get#(TreeNodeResp) get_resp;
    
    // For testing: preload tree nodes
    method Action preload(Level level, TreeIndex index, Bit#(HashWidth) hash);
endinterface

(* synthesize *)
module mkTreeMemory(Ifc_TreeMemory);

    FIFOF#(TreeNodeReq) ff_req <- mkFIFOF;
    FIFOF#(TreeNodeResp) ff_resp <- mkFIFOF;
    
    // Simple storage: level -> RegFile[index]
    // For simulation, we use a flat address space
    // Address = (level << 18) | index
    RegFile#(Bit#(22), Bit#(TAdd#(HashWidth,1))) rf_storage <- mkRegFileFull;
    
    Reg#(Maybe#(TreeNodeReq)) rg_active_req <- mkReg(tagged Invalid);
    Reg#(Vector#(Arity, Bit#(HashWidth))) rg_acc_hashes <- mkReg(replicate(0));
    Reg#(Vector#(Arity, Bool)) rg_acc_valid <- mkReg(replicate(False));
    Reg#(UInt#(4)) rg_sibling_idx <- mkReg(0);

    function Bit#(22) make_addr(Level level, TreeIndex index);
        return {zeroExtend(level), index};
    endfunction
    
    //=====================================================
    // RULE: Accept new request
    //=====================================================
    rule rl_accept_request(!isValid(rg_active_req) && ff_req.notEmpty);
        let req = ff_req.first;
        ff_req.deq;
        
        $display("[TreeMem] Request: L%0d base=%0d mask=%b", 
                req.level, req.base_index, req.sibling_mask);
        
        rg_active_req <= tagged Valid req;
        rg_sibling_idx <= 0;
        rg_acc_hashes <= replicate(0);
        rg_acc_valid <= replicate(False);
    endrule

    //=====================================================
    // RULE: Fetch siblings one at a time
    //=====================================================
    rule rl_fetch_sibling(rg_active_req matches tagged Valid .req);
        TreeIndex idx = req.base_index + zeroExtend(pack(rg_sibling_idx));
        Bit#(22) addr = make_addr(req.level, idx);
        
        // Read one entry per cycle
        let entry = rf_storage.sub(addr);
        Bool is_valid = (entry[valueOf(HashWidth)] == 1'b1);
        
        // Accumulate this sibling
        Vector#(Arity, Bit#(HashWidth)) hashes = rg_acc_hashes;
        Vector#(Arity, Bool) valid = rg_acc_valid;
        
        hashes[rg_sibling_idx] = entry[valueOf(HashWidth)-1:0];
        valid[rg_sibling_idx] = is_valid;
        
        rg_acc_hashes <= hashes;
        rg_acc_valid <= valid;
        
        if (is_valid)
            $display("[TreeMem]   Sibling[%0d] idx=%0d hash=%h", 
                    rg_sibling_idx, idx, hashes[rg_sibling_idx]);
        
        // Move to next sibling or finish
        if (rg_sibling_idx == fromInteger(valueOf(Arity) - 1)) begin
            // All siblings fetched - send response
            ff_resp.enq(TreeNodeResp {
                hashes: hashes,
                valid: valid
            });
            rg_active_req <= tagged Invalid;
            rg_sibling_idx <= 0;
        end else begin
            rg_sibling_idx <= rg_sibling_idx + 1;
        end
    endrule
    
    interface put_req = toPut(ff_req);
    interface get_resp = toGet(ff_resp);
    
    method Action preload(Level level, TreeIndex index, Bit#(HashWidth) hash);
        Bit#(22) addr = make_addr(level, index);
        rf_storage.upd(addr, {1'b1, hash});
        $display("[TreeMem] Preloaded: L%0d[%0d] = %h", level, index, hash);
    endmethod

endmodule

endpackage
