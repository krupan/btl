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
        const longint unsigned reset_value;
        const FieldAttrib attrib;
        longint unsigned value;

        function new(int unsigned lsb_in,
                     int unsigned size_bits_in,
                     string name_in,
                     longint unsigned reset_value_in,
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

        function longint unsigned read();
            return value;
        endfunction

        function void write(longint unsigned val);
            case (attrib)
                RO: begin
                    return;
                end
                RW1C: begin
                    value = 0;
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

    typedef Field Fields[longint unsigned];

    class Reg;
        const string name;
        const longint unsigned offset;
        const int unsigned size_bytes;
        Fields fields;

        function new(string name_in,
                     longint unsigned offset_in,
                     int unsigned size_bytes_in);
            name = name_in;
            offset = offset_in;
            size_bytes = size_bytes_in;
        endfunction

        function void add_fields(Fields fields_in);
            fields = fields_in;
        endfunction

        function bit field_by_name(string name, ref Field field_ref);
            foreach(fields[i]) begin
                if(fields[i].name == name) begin
                    field_ref = fields[i];
                    return 1;
                end
            end
            return 0;
        endfunction

        function void reset();
            foreach(fields[i]) begin
                fields[i].reset();
            end
        endfunction

        function longint unsigned read();
            longint unsigned out;
            foreach(fields[i]) begin
                longint unsigned field_value = fields[i].read();
                for(int unsigned j = fields[i].lsb;
                    j <= fields[i].msb; j++) begin
                    out[j] = field_value[j - fields[i].lsb];
                end
            end
            return out;
        endfunction

        function void write(longint unsigned val);
            foreach(fields[i]) begin
                Field f = fields[i];
                longint unsigned val_slice;
                for(int j = 0; j < f.size_bits; j++) begin
                    val_slice[j] = val[j+f.lsb];
                end
                f.write(val_slice);
            end
        endfunction
    endclass : Reg

    // index is a register offset
    typedef Reg Regs[longint unsigned];

    class AddrMap;
        longint unsigned base_addr;
        longint unsigned size_bytes;
        string name;
        Regs regs;

        function void reset();
            foreach(regs[i]) begin
                regs[i].reset();
            end
        endfunction

        function bit addr_inside(longint unsigned address);
            if(address < base_addr) begin
                return 0;
            end
            if(address > (base_addr + (size_bytes-1))) begin
                return 0;
            end
            return 1;
        endfunction

        function bit reg_by_name(string name, ref Reg reg_ref);
            foreach(regs[i]) begin
                if(regs[i].name == name) begin
                    reg_ref = regs[i];
                    return 1;
                end
            end
            return 0;
        endfunction

        function bit reg_write(longint unsigned addr,
                               longint unsigned value);
            if(!regs.exists(addr)) begin
                return 0;
            end
            regs[addr].write(value);
        endfunction

        function bit reg_read(longint unsigned addr,
                              output longint unsigned value);
            if(!regs.exists(addr)) begin
                return 0;
            end
            value = regs[addr].read();
            return 1;
        endfunction
    endclass : AddrMap
endpackage : btl_regs
