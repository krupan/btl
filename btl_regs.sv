package btl_regs;
    typedef enum {
        RW,
        RO,
        // PCIe spec uses RW1C for write-one-to-clear registers, so we
        // will too
        RW1C
    } FieldAttrib;

    // named after SystemRDL things
    class Field;
        const int unsigned lsb;
        const int unsigned msb;
        const int unsigned size_bits;
        const string name;
        const btl::Value reset_value;
        const FieldAttrib attrib;
        btl::Value value;

        function new(int unsigned lsb_in,
                     int unsigned size_bits_in,
                     string name_in,
                     btl::Value reset_value_in,
                     FieldAttrib attrib_in);
            lsb = lsb_in;
            size_bits = size_bits_in;
            msb = lsb + (size_bits - 1);
            name = name_in;
            reset_value = reset_value_in;
            attrib = attrib_in;
            reset();
        endfunction

        function void reset();
            value = reset_value;
        endfunction

        function btl::Value read();
            return value;
        endfunction

        function void write(btl::Value val);
            case (attrib)
                RO: begin
                    return;
                end
                RW1C: begin
                    for(int i = 0; i < size_bits; i++) begin
                        if(val[i] == 1) begin
                            value[i] = 0;
                        end
                    end
                    return;
                end
                RW: begin
                    value = val;
                end
                default: begin
                    assert(0);
                end
            endcase
        endfunction
    endclass : Field

    typedef Field Fields[btl::Value];

    class Reg;
        const string name;
        const btl::Value offset;
        const int unsigned size_bytes;
        Fields fields;

        function new(string name_in,
                     btl::Address offset_in,
                     int unsigned size_bytes_in);
            name = name_in;
            offset = offset_in;
            size_bytes = size_bytes_in;
        endfunction

        function void add_fields(Fields fields_in);
            fields = fields_in;
        endfunction

        function void field_by_name(string name, ref Field field_ref);
            foreach(fields[i]) begin
                if(fields[i].name == name) begin
                    field_ref = fields[i];
                    return;
                end
            end
            assert(0);
        endfunction

        function void reset();
            foreach(fields[i]) begin
                fields[i].reset();
            end
        endfunction

        function btl::Value read();
            btl::Value out;
            foreach(fields[i]) begin
                btl::Value field_value = fields[i].read();
                for(int unsigned j = fields[i].lsb;
                    j <= fields[i].msb; j++) begin
                    out[j] = field_value[j - fields[i].lsb];
                end
            end
            return out;
        endfunction

        function void write(btl::Value val);
            foreach(fields[i]) begin
                Field f = fields[i];
                btl::Value val_slice;
                for(int j = 0; j < f.size_bits; j++) begin
                    val_slice[j] = val[j+f.lsb];
                end
                f.write(val_slice);
            end
        endfunction
    endclass : Reg

    // index is a register offset
    typedef Reg Regs[btl::Address];

    class AddrMap;
        btl::Address base_addr;
        int unsigned size_bytes;
        string name;
        Regs regs;

        function new(btl::Address base_addr,
                     int unsigned size_bytes);
            this.base_addr = base_addr;
            this.size_bytes = size_bytes;
        endfunction

        function void add_reg(Reg new_reg);
            regs[new_reg.offset] = new_reg;
        endfunction

        function void check_size();
            int unsigned size;
            foreach(regs[i]) begin
                size += regs[i].size_bytes;
            end
            assert(size == size_bytes);
        endfunction

        function void reset();
            foreach(regs[i]) begin
                regs[i].reset();
            end
        endfunction

        function bit addr_inside(btl::Address address);
            if(address < base_addr) begin
                return 0;
            end
            if(address > (base_addr + ({32'h0, size_bytes}-1))) begin
                return 0;
            end
            return 1;
        endfunction

        function void reg_by_name(string name, ref Reg reg_ref);
            foreach(regs[i]) begin
                if(regs[i].name == name) begin
                    reg_ref = regs[i];
                    return;
                end
            end
            assert(0);
        endfunction

        function void reg_write(btl::Address addr,
                                btl::Value value);
            assert(regs.exists(addr) != 0);
            regs[addr].write(value);
        endfunction

        function btl::Value reg_read(btl::Address addr);
            assert(regs.exists(addr) != 0);
            return regs[addr].read();
        endfunction
    endclass : AddrMap
endpackage : btl_regs
