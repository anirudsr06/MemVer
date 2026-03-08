/*
Tree Memory Adapter
Translates abstract tree node requests (level, index) into physical memory requests.
Integrates with the main memory system via DCache_mem_* interfaces.
*/

package tree_memory;

import FIFOF::*;
import FIFO::*;
import GetPut::*;
import Vector::*;
import dcache_types::*;
import mvu::*;
`include "dcache.defines"


interface Ifc_TreeMemory;
    // Tree Read Interface (from MVU)
    interface Put#(TreeNodeReq) put_req;
    interface Get#(TreeNodeResp) get_resp;

    // Tree Write Interface (from MVU or update logic)
    interface Put#(TreeNodeWrite) put_write_req;
    interface Get#(Bool) get_write_resp;

    // Memory Interface (to Memory/Interconnect)
    interface Get#(DCache_mem_readreq#(`paddr)) get_mem_read_req;
    interface Put#(DCache_mem_readresp#(`dbuswidth)) put_mem_read_resp;
    
    method DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8))) mv_mem_write_req;
    method Action ma_mem_write_req_deq;
    interface Put#(Bool) put_mem_write_resp;
endinterface

(* synthesize *)
module mkTreeMemory(Ifc_TreeMemory);

    // Input/Output FIFOs
    FIFOF#(TreeNodeReq) ff_tree_req <- mkFIFOF;
    FIFOF#(TreeNodeResp) ff_tree_resp <- mkFIFOF;
    FIFOF#(TreeNodeWrite) ff_tree_write <- mkFIFOF;
    FIFOF#(Bool) ff_tree_write_resp <- mkFIFOF;

    // Memory Interface FIFOs
    FIFOF#(DCache_mem_readreq#(`paddr)) ff_mem_read_req <- mkFIFOF;
    FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_mem_read_resp <- mkFIFOF;
    FIFOF#(DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8)))) ff_mem_write_req <- mkFIFOF;
    FIFOF#(Bool) ff_mem_write_resp <- mkFIFOF;

    // Address constants (Must match hcache.bsv)
    Bit#(`paddr) tree_base = 'h8520_0000;
    Bit#(`paddr) level1_offset = 'h0000_0000;
    Bit#(`paddr) level2_offset = 'h0004_0000;

    // Internal state for read accumulation
    Reg#(UInt#(4)) rg_beat_count <- mkReg(0);
    Vector#(Arity, Reg#(Bit#(HashWidth))) rg_acc_hashes <- replicateM(mkReg(0));
    Vector#(Arity, Reg#(Bool)) rg_acc_valid <- replicateM(mkReg(False));
    Reg#(TreeNodeReq) rg_current_req <- mkReg(?);
    Reg#(Bool) rg_processing_read <- mkReg(False);

    // Address calculation helper
    function Bit#(`paddr) get_node_addr(Level level, TreeIndex index);
        Bit#(`paddr) level_offset = (level == 1) ? level1_offset : level2_offset;
        Bit#(`paddr) node_offset = zeroExtend(index) << 3; // 8 bytes per node
        return tree_base + level_offset + node_offset;
    endfunction

    //=====================================================
    // Read Path
    //=====================================================

    // 1. Process new read request
    rule rl_process_read_req(ff_tree_req.notEmpty && !rg_processing_read);
        let req = ff_tree_req.first;
        ff_tree_req.deq;

        // Calculate address for the base index (first of 8 siblings)
        let addr = get_node_addr(req.level, req.base_index);
        
        $display("[TreeMem] Read Req: L%0d[%0d] -> PhysAddr %h", req.level, req.base_index, addr);

        // Issue burst read check for 8 siblings (64 bytes)
        // burst_len = 7 means 8 beats
        ff_mem_read_req.enq(DCache_mem_readreq {
            address: addr,
            burst_len: 7,
            burst_size: 3, // 8 bytes (64-bit)
            io: False
        });

        rg_current_req <= req;
        rg_processing_read <= True;
        rg_beat_count <= 0;
        for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
            rg_acc_hashes[i] <= 0;
            rg_acc_valid[i] <= False;
        end
    endrule

    // 2. Process memory responses
    rule rl_process_read_resp(rg_processing_read && ff_mem_read_resp.notEmpty);
        let resp = ff_mem_read_resp.first;
        ff_mem_read_resp.deq;

        rg_acc_hashes[rg_beat_count] <= truncate(resp.data);
        rg_acc_valid[rg_beat_count] <= True;

        $display("[TreeMem]   Beat %0d: %h", rg_beat_count, resp.data);

        if (resp.last) begin
            // Done with burst
            Vector#(Arity, Bit#(HashWidth)) hashes = replicate(0);
            Vector#(Arity, Bool) v = replicate(False);
            for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
                hashes[i] = rg_acc_hashes[i];
                v[i] = rg_acc_valid[i];
            end
            // Ensure the CURRENT beat is included in the output vector 
            // since rg_acc_hashes update is not visible until next cycle
            hashes[rg_beat_count] = truncate(resp.data);
            v[rg_beat_count] = True;

            ff_tree_resp.enq(TreeNodeResp {
                hashes: hashes,
                valid: v
            });
            rg_processing_read <= False;
            
            // Sanity check
             if (rg_beat_count != 7) 
                $display("[TreeMem] ERROR: Received %0d beats, expected 8!", rg_beat_count + 1);
        end else begin
            rg_beat_count <= rg_beat_count + 1;
        end
    endrule

    //=====================================================
    // Write Path
    //=====================================================

    rule rl_process_write_req(ff_tree_write.notEmpty);
        let req = ff_tree_write.first;
        ff_tree_write.deq;

        let addr = get_node_addr(req.level, req.index);
        
        $display("[TreeMem] Write Req: L%0d[%0d] = %h -> PhysAddr %h", 
                req.level, req.index, req.hash, addr);

        ff_mem_write_req.enq(DCache_mem_writereq {
            address: addr, // Pass full unaligned address
            data: zeroExtend(req.hash), // No need to shift; ccore takes truncate(data) directly
            burst_len: fromInteger(valueOf(`dblocks)-1), // 8 beats
            burst_size: fromInteger(valueOf(TLog#(`dwords))), // 8 bytes per beat
            io: False
        });
    endrule

    rule rl_process_write_resp(ff_mem_write_resp.notEmpty);
        let resp = ff_mem_write_resp.first;
        ff_mem_write_resp.deq;
        ff_tree_write_resp.enq(resp);
        $display("[TreeMem] Write Complete");
    endrule

    //=====================================================
    // Interfaces
    //=====================================================

    interface put_req = toPut(ff_tree_req);
    interface get_resp = toGet(ff_tree_resp);

    interface put_write_req = toPut(ff_tree_write);
    interface get_write_resp = toGet(ff_tree_write_resp);

    interface get_mem_read_req = toGet(ff_mem_read_req);
    interface put_mem_read_resp = toPut(ff_mem_read_resp);

    method DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8))) mv_mem_write_req;
        return ff_mem_write_req.first;
    endmethod

    method Action ma_mem_write_req_deq;
        ff_mem_write_req.deq;
    endmethod
    
    interface put_mem_write_resp = toPut(ff_mem_write_resp);

endmodule

endpackage
