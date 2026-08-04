package btl_regs;
    typedef enum {
        RW,
        RO,
        // PCIe spec uses RW1C for write-one-to-clear registers, so we
        // will too
        RW1C
    } FieldAttrib;

    typedef enum {
        FIELD,
        REG,
        ADDRMAP
    } ObjType;

    class Base;
        const string name;
        Base children[$];
        // this is just so we don't have to cast
        ObjType my_type;
        btl::Address base_addr;
        const btl::Value offset;
        const int unsigned size_bytes;

        virtual function void reset();
            foreach(children[i]) begin
                children[i].reset();
            end
        endfunction
    endclass

    // named after SystemRDL things
    class Field extends Base;
        const int unsigned lsb;
        const int unsigned msb;
        const int unsigned size_bits;
        const btl::Value reset_value;
        const FieldAttrib attrib;
        btl::Value value;

        function new(string name_in,
                     FieldAttrib attrib_in,
                     btl::Value reset_value_in,
                     int unsigned msb_in,
                     int unsigned lsb_in);
            name = name_in;
            attrib = attrib_in;
            reset_value = reset_value_in;
            lsb = lsb_in;
            msb = msb_in;
            size_bits = msb - lsb + 1;
            reset();
            my_type = FIELD;
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

    class Reg extends Base;

        function new(string name,
                     int unsigned size_bytes,
                     btl::Address offset);
            this.name = name;
            this.size_bytes = size_bytes;
            this.offset = offset;
            my_type = REG;
        endfunction

        function btl::Value read();
            btl::Value out;
            foreach(children[i]) begin
                btl::Value field_value = children[i].read();
                for(btl::Address j = children[i].lsb; j <= children[i].msb; j++)
                begin
                    out[j] = field_value[j - children[i].lsb];
                end
            end
            return out;
        endfunction

        function void write(btl::Value val);
            foreach(children[i]) begin
                Field f = children[i];
                btl::Value val_slice;
                for(int j = 0; j < f.size_bits; j++) begin
                    val_slice[j] = val[j+f.lsb];
                end
                f.write(val_slice);
            end
        endfunction
    endclass : Reg

    class AddrMap;

        function new(int unsigned size_bytes, btl::Address base_addr);
            this.base_addr = base_addr;
            this.size_bytes = size_bytes;
            my_type = ADDRMAP;
        endfunction

        function bit addr_inside(btl::Address address);
            if(my_type == FIELD) begin
                assert(0);
            end
            if(address < base_addr) begin
                return 0;
            end
            if(address > (base_addr + ({32'h0, size_bytes}-1))) begin
                return 0;
            end
            return 1;
        endfunction

        function bit get_reg_by_addr(btl::Address addr,
                                     ref btl_regs::Reg the_reg);
            if(!addr_inside(addr)) begin
                return 0;
            end
            foreach(children[i]) begin
                if(children[i].my_type == REG) begin
                    btl::Address address = base_addr + children[i].offset;
                    if(addr == address) begin
                        the_reg = children[i];
                        return 1;
                    end
                end
                if(children[i].get_reg_by_addr(addr, the_reg)) begin
                    return 1;
                end
            end
            return 0;
        endfunction
    endclass : AddrMap
endpackage : btl_regs
