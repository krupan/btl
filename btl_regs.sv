// NOTE: we can't name anything reg (because that's a SystemVerilog
// keyword) or register (because that's a C++ keyword and verilator
// complains)

package btl_regs;
    typedef enum {
        // readable and writable
        RW,
        // read-only
        RO,
        // write 1 to clear, writing 0 does nothing
        WOCLR,
        // write 1 to set, writing 0 does nothing
        WOSET
    } FieldAttrib;

    typedef enum {
        FIELD,
        REG,
        ADDRMAP
    } ObjType;

    class Base;
        const string name;
        Base children[$];
        // this is so we don't have to cast to determine the type
        const ObjType my_type;
        // absolute address of this addrmap or register
        btl::Address address;
        const btl::Value size_bytes;
        // offset from address of parent addrmap
        const btl::Value offset;

        // const members can only be assigned to in the base class
        // constructor, according to dave_59:
        // https://stackoverflow.com/a/60803249/27729
        function new(string name,
                     ObjType my_type,
                     btl::Value size_bytes,
                     btl::Value offset);
            this.name = name;
            this.my_type = my_type;
            this.size_bytes = size_bytes;
            this.offset = offset;
        endfunction

        function void set_base_addr(btl::Address address);
            string indent = "";
            if(my_type == FIELD) return;
            if(my_type == REG) begin
                indent = "  ";
            end
            this.address = address + this.offset;
            $display("%s%s base: 0x%0x, offset: 0x%0x, address: 0x%0x", indent, name, address, this.offset, this.address);
            if(children.size() > 0 && my_type != REG) begin
                $display("%scalling set_base_addr(0x%0x) for each my children", indent, this.address);
            end
            foreach(children[i]) begin
                children[i].set_base_addr(this.address);
            end
        endfunction

        virtual function void reset();
            foreach(children[i]) begin
                children[i].reset();
            end
        endfunction
    endclass : Base

    // named after SystemRDL things
    class Field extends Base;
        const btl::Value lsb;
        const btl::Value msb;
        const btl::Value size_bits;
        const btl::Value reset_value;
        const FieldAttrib sw_attrib;
        const FieldAttrib hw_attrib;
        bit resetable;
        btl::Value value;

        function new(string name,
                     FieldAttrib sw_attrib,
                     FieldAttrib hw_attrib,
                     bit resetable,
                     btl::Value reset_value,
                     btl::Value msb,
                     btl::Value lsb);
            super.new(name, FIELD, 0, 0);
            this.sw_attrib = sw_attrib;
            this.hw_attrib = hw_attrib;
            this.resetable = resetable;
            this.reset_value = reset_value;
            this.lsb = lsb;
            this.msb = msb;
            size_bits = msb - lsb + 1;
            reset();
        endfunction

        function void reset();
            if(resetable) begin
                value = reset_value;
            end
        endfunction

        function btl::Value read();
            return value;
        endfunction

        function void write(btl::Value val);
            case (sw_attrib)
                RO: begin
                    return;
                end
                WOCLR: begin
                    for(int i = 0; i < size_bits[31:0]; i++) begin
                        if(val[i] == 1) begin
                            value[i] = 0;
                        end
                    end
                    return;
                end
                WOSET: begin
                    for(int i = 0; i < size_bits[31:0]; i++) begin
                        if(val[i] == 1) begin
                            value[i] = 1;
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

        function void hw_write(btl::Value val);
            case (hw_attrib)
                RO: begin
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
                     btl::Value size_bytes,
                     btl::Address offset);
            super.new(name, REG, size_bytes, offset);
        endfunction

        function btl::Value read();
            btl::Value out;
            foreach(children[i]) begin
                Field field;
                btl::Value field_value;
                assert($cast(field, children[i]));
                field_value = field.read();
                for(btl::Value j = field.lsb; j <= field.msb; j++) begin
                    int field_ind = j[31:0] - field.lsb[31:0];
                    out[j[31:0]] = field_value[field_ind];
                end
            end
            return out;
        endfunction

        function void write(btl::Value val, bit hw = 0);
            foreach(children[i]) begin
                Field field;
                btl::Value val_slice;
                assert($cast(field, children[i]));
                for(int j = 0; j < field.size_bits[31:0]; j++) begin
                    val_slice[j] = val[j + field.lsb[31:0]];
                end
                if(hw) begin
                    field.hw_write(val_slice);
                end
                else begin
                    field.write(val_slice);
                end
            end
        endfunction

        function void hw_write(btl::Value val);
            write(val, 1);
        endfunction
    endclass : Reg

    class ReservedReg extends btl_regs::Reg;
        // class members
        btl_regs::Field reserved;
        function new(string name,
                     btl::Value size_bytes,
                     btl::Address offset);
            super.new(name, size_bytes, offset);
            reserved = new("reserved",
                           btl_regs::RO,
                           btl_regs::RO,
                           1'b1,
                           'h0,
                           63,
                           0);
            children.push_back(reserved);
        endfunction : new
    endclass : ReservedReg

    class AddrMap extends Base;
        function new(string name,
                     btl::Value size_bytes,
                     btl::Address offset);
            super.new(name, ADDRMAP, size_bytes, offset);
        endfunction

        function bit addr_inside(btl::Address address);
            if(address < this.address) begin
                $display("%s: address too low", name);
                return 0;
            end
            if(address > (this.address + size_bytes - 1)) begin
                $display("%s: address too high", name);
                return 0;
            end
            $display("%s: address just right", name);
            return 1;
        endfunction

        function bit get_reg_by_addr(btl::Address address,
                                     ref btl_regs::Reg the_reg);
            ReservedReg reserved;
            if(!addr_inside(address)) begin
                return 0;
            end
            foreach(children[i]) begin
                AddrMap addrmap;
                case(children[i].my_type)
                    REG: begin
                        btl::Address reg_addr = children[i].address;
                        if(address == reg_addr) begin
                            assert($cast(the_reg, children[i]));
                            return 1;
                        end
                    end
                    ADDRMAP: begin
                        assert($cast(addrmap, children[i]));
                        if(addrmap.get_reg_by_addr(address, the_reg)) begin
                            return 1;
                        end
                    end
                    default: begin
                        $display("bug in btl_regs: my_type: %s, children[%0d].my_type: %s",
                                 my_type.name, i, children[i].my_type.name);
                        assert(0);
                        return 0;
                    end
                endcase
            end
            reserved = new("reserved", 8, address);
            $display("no register at this address, returning reserved reg");
            the_reg = reserved;
            return 1;
        endfunction

        function bit reg_write(btl::Address address, btl::Value val);
            Reg the_reg;
            if(get_reg_by_addr(address, the_reg)) begin
                the_reg.write(val);
                return 1;
            end
            return 0;
        endfunction

        function bit reg_read(btl::Address address, output btl::Value val);
            Reg the_reg;
            if(get_reg_by_addr(address, the_reg)) begin
                val = the_reg.read();
                return 1;
            end
            return 0;
        endfunction
    endclass : AddrMap
endpackage : btl_regs
