package unified_memory;
    import FIFOF::*;
    import FIFO::*;
    import GetPut::*;
    import Connectable::*;
    import Vector::*;
    import RegFile::*;
    import dcache_types::*;
    `include "dcache.defines"

    // Memory Port Interface
    interface Ifc_MemoryPort;
        interface Put#(DCache_mem_readreq#(`paddr)) put_read_req;
        interface Get#(DCache_mem_readresp#(`dbuswidth)) get_read_resp;
        interface Put#(DCache_mem_writereq#(`paddr, `dbuswidth)) put_write_req;
        interface Get#(Bool) get_write_resp;
    endinterface

    interface Ifc_UnifiedMemory;
        interface Ifc_MemoryPort data_port;
        interface Ifc_MemoryPort tree_port;
        
        // Backdoor initialization
        method Action write_mem(Bit#(`paddr) addr, Bit#(64) data);
    endinterface

    // Address remapping for compact storage:
    //   Data region:  0x8000_0000 - 0x801F_FFFF  (2MB = 256K words) -> indices 0x00000 - 0x3FFFF
    //   Tree region:  0x8020_0000 - 0x8027_FFFF  (512KB = 64K words) -> indices 0x40000 - 0x4FFFF
    //   Below 0x8000_0000: direct map (addr >> 3) for any low-address test data (truncated)
    // Total needed: ~320K entries = 19 bits is sufficient
    typedef 19 MemIndexWidth;

    (* synthesize *)
    module mkUnifiedMemory(Ifc_UnifiedMemory);
        
        // Shared Storage
        RegFile#(Bit#(MemIndexWidth), Bit#(64)) rf_mem <- mkRegFileFull;
        
        // Remap physical addresses to compact memory indices
        function Bit#(MemIndexWidth) addr_to_idx(Bit#(`paddr) addr);
            if (addr >= 'h8020_0000) begin
                // Tree region: remap to indices starting at 0x40000
                Bit#(`paddr) offset = addr - 'h8020_0000;
                return truncate((offset >> 3) + 'h40000);
            end else if (addr >= 'h8000_0000) begin
                // Data region: remap to indices starting at 0x00000
                Bit#(`paddr) offset = addr - 'h8000_0000;
                return truncate(offset >> 3);
            end else begin
                // Low addresses (shouldn't hit in normal use but safe fallback)
                return truncate(addr >> 3);
            end
        endfunction

        // ===============================================================
        // Port 0: Data
        // ===============================================================
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_data_read_req <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_data_read_resp <- mkFIFOF;
        FIFOF#(DCache_mem_writereq#(`paddr, `dbuswidth)) ff_data_write_req <- mkFIFOF;
        FIFOF#(Bool) ff_data_write_resp <- mkFIFOF;

        Reg#(Bit#(8)) rg_data_burst_count <- mkReg(0);
        Reg#(DCache_mem_readreq#(`paddr)) rg_data_current_req <- mkReg(?);

        // Handle Read
        rule rl_data_read_start(ff_data_read_req.notEmpty && rg_data_burst_count == 0);
            let req = ff_data_read_req.first;
            ff_data_read_req.deq;
            rg_data_current_req <= req;
            rg_data_burst_count <= req.burst_len + 1;
            
            $display("[UniMem:Data] Read Req Addr=%h Burst=%d", req.address, req.burst_len);
        endrule

        rule rl_data_read_burst(rg_data_burst_count > 0);
            let addr = rg_data_current_req.address;
            Bit#(`paddr) burst_offset = zeroExtend((rg_data_current_req.burst_len + 1) - rg_data_burst_count);
            Bit#(`paddr) current_addr = addr + (burst_offset << 3);
            
            let data = rf_mem.sub(addr_to_idx(current_addr));
            
            ff_data_read_resp.enq(DCache_mem_readresp {
                data: data,
                last: (rg_data_burst_count == 1),
                err: False
            });
            
            rg_data_burst_count <= rg_data_burst_count - 1;
            $display("[UniMem:Data] Sending beat data=%h (addr=%h)", data, current_addr);
        endrule

        // Handle Write
        rule rl_data_write(ff_data_write_req.notEmpty);
            let req = ff_data_write_req.first;
            ff_data_write_req.deq;
            
            rf_mem.upd(addr_to_idx(req.address), req.data);
            ff_data_write_resp.enq(True);
            
            $display("[UniMem:Data] Write Addr=%h Data=%h", req.address, req.data);
        endrule

        // ===============================================================
        // Port 1: Tree
        // ===============================================================
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_tree_read_req <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_tree_read_resp <- mkFIFOF;
        FIFOF#(DCache_mem_writereq#(`paddr, `dbuswidth)) ff_tree_write_req <- mkFIFOF;
        FIFOF#(Bool) ff_tree_write_resp <- mkFIFOF;

        Reg#(Bit#(8)) rg_tree_burst_count <- mkReg(0);
        Reg#(DCache_mem_readreq#(`paddr)) rg_tree_current_req <- mkReg(?);

        // Handle Read
        rule rl_tree_read_start(ff_tree_read_req.notEmpty && rg_tree_burst_count == 0);
            let req = ff_tree_read_req.first;
            ff_tree_read_req.deq;
            rg_tree_current_req <= req;
            rg_tree_burst_count <= req.burst_len + 1;
            
            $display("[UniMem:Tree] Read Req Addr=%h Burst=%d", req.address, req.burst_len);
        endrule

        rule rl_tree_read_burst(rg_tree_burst_count > 0);
            let addr = rg_tree_current_req.address;
            Bit#(`paddr) burst_offset = zeroExtend((rg_tree_current_req.burst_len + 1) - rg_tree_burst_count);
            Bit#(`paddr) current_addr = addr + (burst_offset << 3);
            
            let data = rf_mem.sub(addr_to_idx(current_addr));
            
            ff_tree_read_resp.enq(DCache_mem_readresp {
                data: data,
                last: (rg_tree_burst_count == 1),
                err: False
            });
            
            rg_tree_burst_count <= rg_tree_burst_count - 1;
            $display("[UniMem:Tree] Sending beat data=%h (addr=%h)", data, current_addr);
        endrule

        // Handle Write
        rule rl_tree_write(ff_tree_write_req.notEmpty);
            let req = ff_tree_write_req.first;
            ff_tree_write_req.deq;
            
            rf_mem.upd(addr_to_idx(req.address), req.data);
            ff_tree_write_resp.enq(True);
            
            $display("[UniMem:Tree] Write Addr=%h Data=%h", req.address, req.data);
        endrule

        // ===============================================================
        // Interfaces
        // ===============================================================

        interface Ifc_MemoryPort data_port;
            interface put_read_req = toPut(ff_data_read_req);
            interface get_read_resp = toGet(ff_data_read_resp);
            interface put_write_req = toPut(ff_data_write_req);
            interface get_write_resp = toGet(ff_data_write_resp);
        endinterface

        interface Ifc_MemoryPort tree_port;
            interface put_read_req = toPut(ff_tree_read_req);
            interface get_read_resp = toGet(ff_tree_read_resp);
            interface put_write_req = toPut(ff_tree_write_req);
            interface get_write_resp = toGet(ff_tree_write_resp);
        endinterface

        method Action write_mem(Bit#(`paddr) addr, Bit#(64) data);
            rf_mem.upd(addr_to_idx(addr), data);
            $display("[UniMem] Backdoor Write Addr=%h Data=%h", addr, data);
        endmethod

    endmodule

endpackage
