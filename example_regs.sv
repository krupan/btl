package example_regs;
    class ExampleRegs extends btl_regs::AddrMap;
        btl_regs::Reg csr_a;
        btl_regs::Reg csr_b;

        function new(longint unsigned base_addr,
                     int unsigned size_bytes);
            btl_regs::Fields f;
            super.new(base_addr, size_bytes);
            csr_a = new("csr_a", 'h0, 4);
            regs['h0] = csr_a;
            csr_b = new("csr_b", 'h4, 4);
            regs['h4] = csr_b;

            f[0] = new(0, 3, "power_state", 'b101, btl_regs::RW);
            f[1] = new(3, 5, "error_status", 'h0, btl_regs::RW1C);
            f[2] = new(8, 24, "message", 'h0, btl_regs::RW);
            csr_a.add_fields(f);
            f = '{};

            f[0] = new(0, 8, "ID", 'h0, btl_regs::RO);
            f[1] = new(0, 8, "class", 'h0, btl_regs::RO);
            f[2] = new(0, 8, "version", 'h0, btl_regs::RO);
            f[3] = new(0, 1, "enable", 'h0, btl_regs::RW);
            csr_b.add_fields(f);

            add_reg(csr_a);
            add_reg(csr_b);
            check_size();
        endfunction
    endclass
endpackage : example_regs
